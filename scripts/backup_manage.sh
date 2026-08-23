#!/usr/bin/env bash
export LANG=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SELECTED_BACKUP_FILE=""

is_safe_backup_project_id() {
    local id="$1"
    case "$id" in
        ''|.|..|backup|backups|"$DNT_STATE_DIR_NAME"|*/*) return 1 ;;
        *) return 0 ;;
    esac
}

backup_file_project_id() {
    local file_name="$1" id
    file_name="$(basename "$file_name")"
    if [[ "$file_name" =~ ^(.+)-[0-9]{8}-[0-9]{4}(-[0-9]+)?\.tar\.gz$ ]]; then
        id="${BASH_REMATCH[1]}"
        is_safe_backup_project_id "$id" && printf '%s' "$id"
    fi
}

backup_file_day() {
    local file_name="$1" compact_day
    file_name="$(basename "$file_name")"
    if [[ "$file_name" =~ ^.+-([0-9]{8})-[0-9]{4}(-[0-9]+)?\.tar\.gz$ ]]; then
        compact_day="${BASH_REMATCH[1]}"
        printf '%s-%s-%s' "${compact_day:0:4}" "${compact_day:4:2}" "${compact_day:6:2}"
    else
        printf '%s' '未知日期'
    fi
}

backup_file_size() {
    local file="$1" size
    size="$(du -h "$file" 2>/dev/null | awk 'NR == 1 { print $1 }')"
    printf '%s' "${size:-未知}"
}

list_backup_project_ids() {
    local file id
    [ -d "$BACKUP_DIR" ] || return 0
    while IFS= read -r file; do
        id="$(backup_file_project_id "$file")"
        [ -n "$id" ] && printf '%s\n' "$id"
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' -print 2>/dev/null) | LC_ALL=C sort -u
}

list_backup_files_for_project() {
    local id="$1" file backup_id
    [ -d "$BACKUP_DIR" ] || return 0
    while IFS= read -r file; do
        backup_id="$(backup_file_project_id "$file")"
        [ "$backup_id" = "$id" ] && printf '%s\n' "$file"
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' -print 2>/dev/null) | LC_ALL=C sort -r
}

backup_version_count() {
    local id="$1"
    list_backup_files_for_project "$id" | awk 'NF { count++ } END { print count + 0 }'
}

backup_project_app_status() {
    local id="$1" path
    path="$(app_project_path "$id")"
    if [ -d "$path" ]; then
        green "存在：$path"
    elif [ -e "$path" ]; then
        yellow "存在同名文件：$path"
    else
        muted "不存在：$path"
    fi
}

backup_project_install_status() {
    local id="$1"
    if ! docker_available || ! compose_cmd_available; then
        muted "无法检测（Docker Compose 未就绪）"
    elif project_is_installed "$id"; then
        green "已安装（存在 Docker 容器）"
    else
        muted "未安装"
    fi
}

backup_archive_is_valid_for_project() {
    local archive="$1" id="$2" entry
    [ -f "$archive" ] || {
        red "备份文件不存在：$archive"
        return 1
    }
    is_safe_backup_project_id "$id" || {
        red "备份项目 ID 不安全，已拒绝操作。"
        return 1
    }

    # 仅接受由本工具生成的“项目目录及其内容”结构，避免压缩包在解压时写出 /app/<项目>。
    while IFS= read -r entry; do
        case "$entry" in
            "$id"|"$id"/*) ;;
            *)
                red "备份包目录结构异常，已拒绝解压：$entry"
                return 1
                ;;
        esac
        case "$entry" in
            /*|*'/../'*|../*|*/..|.)
                red "备份包包含不安全路径，已拒绝解压。"
                return 1
                ;;
        esac
    done < <(tar -tzf "$archive" 2>/dev/null) || return 1

    if ! tar -tzf "$archive" >/dev/null 2>&1; then
        red "无法读取备份包，可能已损坏：$archive"
        return 1
    fi
    return 0
}

prepare_backup_destination() {
    local id="$1" target_path answer
    target_path="$(app_project_path "$id")"
    if [ -e "$target_path" ]; then
        yellow "检测到当前项目目录：$target_path"
        readp "  解压会覆盖现有目录，是否继续？[y/N] → " answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            yellow "已取消，未解压备份。"
            return 1
        fi
        if project_is_installed "$id"; then
            yellow "正在停止现有 Docker 项目（不会删除 Docker volumes）…"
            compose_run "$target_path" down || {
                red "无法停止现有项目，已取消覆盖。"
                return 1
            }
            remove_project_install_order "$id"
        fi
        rm -rf "$target_path" || return 1
    fi
    mkdir -p "$TARGET_BASE_DIR"
}

extract_backup_to_app() {
    local archive="$1" id="$2"
    backup_archive_is_valid_for_project "$archive" "$id" || return 1
    prepare_backup_destination "$id" || return 1
    pink ">>> 正在解压备份到 $(app_project_path "$id")"
    tar -xzf "$archive" -C "$TARGET_BASE_DIR" --no-same-owner || {
        red "解压失败。"
        return 1
    }
    [ -d "$(app_project_path "$id")" ] || {
        red "解压完成但未找到项目目录，已取消后续操作。"
        return 1
    }
    green "备份已解压：$(app_project_path "$id")"
}

restore_backup_and_install() {
    local archive="$1" id="$2" path
    extract_backup_to_app "$archive" "$id" || return 1
    path="$(app_project_path "$id")"
    if [ ! -f "$path/docker-compose.yml" ]; then
        red "备份中没有 docker-compose.yml，无法安装项目。"
        return 1
    fi
    compose_cmd_available || {
        red "未检测到 Docker Compose，项目已解压但尚未安装。"
        return 1
    }
    pink ">>> 正在拉取并安装 $id"
    compose_run "$path" pull || return 1
    record_project_image_versions "$id"
    compose_run "$path" up -d || return 1
    record_project_image_versions "$id"
    record_project_install_order "$id" || return 1
    green "已恢复并安装项目：$id"
}

delete_backup_file() {
    local archive="$1" answer
    [ -f "$archive" ] || {
        red "备份文件不存在：$archive"
        return 1
    }
    red "即将删除备份：$(basename "$archive")"
    confirm_action "  确认删除此备份" || {
        yellow "已取消删除。"
        return 1
    }
    rm -f "$archive" || return 1
    green "备份已删除。"
}

select_backup_version() {
    local id="$1" files=() file i choice
    while IFS= read -r file; do
        [ -n "$file" ] && files+=("$file")
    done < <(list_backup_files_for_project "$id")
    if [ "${#files[@]}" -eq 0 ]; then
        yellow "该项目没有可用备份。"
        return 1
    fi

    qiqi_section "选择备份版本"
    i=1
    for file in "${files[@]}"; do
        printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} %s  ${QIQI_WHITE}(%s)${QIQI_PLAIN}\n" \
            "$i" "$(backup_file_day "$file")" "$(backup_file_size "$file")"
        i=$((i + 1))
    done
    printf "  ${QIQI_GREEN}[ 0 ]${QIQI_PLAIN} ${QIQI_WHITE}返回${QIQI_PLAIN}\n\n"
    readp "  请选择要操作的备份版本 → " choice
    [ "$choice" = "0" ] && return 1
    case "$choice" in ''|*[!0-9]*) red "无效选项。"; return 1 ;; esac
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#files[@]}" ]; then
        red "无效选项。"
        return 1
    fi
    SELECTED_BACKUP_FILE="${files[$((choice - 1))]}"
}

backup_project_detail_menu() {
    local id="$1" choice count file version
    while true; do
        clear
        qiqi_banner "$PROJECT_TITLE" "$PROJECT_VERSION" "备份管理" "$PROJECT_URL"
        count="$(backup_version_count "$id")"
        qiqi_section "备份项目详情"
        printf "  ${QIQI_GREEN}项目 ID${QIQI_PLAIN}: %s\n" "$id"
        printf "  ${QIQI_GREEN}已备份版本${QIQI_PLAIN}: %s\n" "$count"
        printf "  ${QIQI_GREEN}/app 项目目录${QIQI_PLAIN}: "; backup_project_app_status "$id"
        printf "  ${QIQI_GREEN}项目安装状态${QIQI_PLAIN}: "; backup_project_install_status "$id"
        qiqi_section "备份时间（按日）"
        version=1
        while IFS= read -r file; do
            [ -n "$file" ] || continue
            printf "  ${QIQI_WHITE}• 版本 %s：%s${QIQI_PLAIN}\n" "$version" "$(backup_file_day "$file")"
            version=$((version + 1))
        done < <(list_backup_files_for_project "$id")
        qiqi_section "操作"
        qiqi_menu_item "1" "解压备份"
        qiqi_menu_item "2" "恢复备份（解压并安装）"
        qiqi_menu_item "3" "删除备份"
        qiqi_menu_item "0" "返回备份项目列表"
        echo
        readp "  请输入选项 → " choice
        case "$choice" in
            1)
                select_backup_version "$id" && extract_backup_to_app "$SELECTED_BACKUP_FILE" "$id"
                pause
                ;;
            2)
                select_backup_version "$id" && restore_backup_and_install "$SELECTED_BACKUP_FILE" "$id"
                pause
                ;;
            3)
                select_backup_version "$id" && delete_backup_file "$SELECTED_BACKUP_FILE"
                [ "$(backup_version_count "$id")" -gt 0 ] || return 0
                pause
                ;;
            0) return 0 ;;
            *) red "无效选项。"; sleep 1 ;;
        esac
    done
}

backup_manage_menu() {
    local ids=() id i choice
    while true; do
        ids=()
        while IFS= read -r id; do
            [ -n "$id" ] && ids+=("$id")
        done < <(list_backup_project_ids)
        clear
        qiqi_banner "$PROJECT_TITLE" "$PROJECT_VERSION" "备份管理" "$PROJECT_URL"
        qiqi_section "备份项目"
        if [ "${#ids[@]}" -eq 0 ]; then
            yellow "  未找到备份文件：$BACKUP_DIR"
            muted "  项目更新时会自动创建备份。"
        else
            i=1
            for id in "${ids[@]}"; do
                printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} %s  ${QIQI_WHITE}（%s 个版本）${QIQI_PLAIN}\n" \
                    "$i" "$id" "$(backup_version_count "$id")"
                i=$((i + 1))
            done
        fi
        printf "  ${QIQI_GREEN}[ 0 ]${QIQI_PLAIN} ${QIQI_WHITE}返回主菜单${QIQI_PLAIN}\n\n"
        readp "  请输入选项 → " choice
        case "$choice" in
            0) return 0 ;;
            ''|*[!0-9]*) red "无效选项。"; sleep 1 ;;
            *)
                if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#ids[@]}" ] 2>/dev/null; then
                    backup_project_detail_menu "${ids[$((choice - 1))]}"
                else
                    red "无效选项。"
                    sleep 1
                fi
                ;;
        esac
    done
}

main() {
    require_root
    backup_manage_menu
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
