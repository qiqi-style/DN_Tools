#!/usr/bin/env bash
export LANG=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SELECTED_PROJECT_ID=""

array_from_lines() {
    local __name="$1" text="${2:-}" line
    eval "$__name=()"
    if [ "$#" -ge 2 ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && eval "$__name+=(\"\$line\")"
        done << EOF
$text
EOF
    else
        while IFS= read -r line; do
            [ -n "$line" ] && eval "$__name+=(\"\$line\")"
        done
    fi
}

show_project_detail() {
    local id="$1" path compose_file local_url public_url containers images health_url
    path="$(project_runtime_path "$id")"
    compose_file="$path/docker-compose.yml"
    load_project_meta "$id"
    local_url="$(project_local_url "$id")"
    public_url="$(project_public_url "$id")"
    health_url="${HEALTH_URL:-$local_url}"
    containers="$(project_container_names "$compose_file")"
    images="${IMAGE_VERSION:-$(project_images "$compose_file")}"
    [ -n "$containers" ] || containers="未识别"
    [ -n "$images" ] || images="未识别"

    qiqi_section "项目详情"
    printf "  ${QIQI_GREEN}项目名称${QIQI_PLAIN}: %s ${QIQI_WHITE}(%s)${QIQI_PLAIN}\n" "$PROJECT_NAME" "$id"
    printf "  ${QIQI_GREEN}功能说明${QIQI_PLAIN}: %s\n" "$DESCRIPTION"
    printf "  ${QIQI_GREEN}项目地址${QIQI_PLAIN}: %s\n" "${PROJECT_META_URL:-未配置}"
    printf "  ${QIQI_GREEN}运行目录${QIQI_PLAIN}: %s\n" "$path"
    printf "  ${QIQI_GREEN}容器名称${QIQI_PLAIN}: %s\n" "$containers"
    printf "  ${QIQI_GREEN}镜像版本${QIQI_PLAIN}: %s\n" "$images"
    printf "  ${QIQI_GREEN}当前状态${QIQI_PLAIN}: %b\n" "$(project_running_status "$id")"
    printf "  ${QIQI_GREEN}内网地址${QIQI_PLAIN}: %s %b\n" "$local_url" "$(check_url "$health_url")"
    printf "  ${QIQI_GREEN}外网地址${QIQI_PLAIN}: %s %b\n" "$public_url" "$(check_url "$public_url")"
    printf "  ${QIQI_GREEN}版本记录${QIQI_PLAIN}: 安装/更新时通过 docker compose pull 写入 dntool-config/project.conf\n"
}

show_all_installed_summary() {
    local ids=() id local_url public_url
    array_from_lines ids "$(collect_installed_ids)"
    [ "${#ids[@]}" -gt 0 ] || return 0

    qiqi_section "已安装项目"
    for id in "${ids[@]}"; do
        load_project_meta "$id"
        local_url="$(project_local_url "$id")"
        public_url="$(project_public_url "$id")"
        printf "  ${QIQI_GREEN}-${QIQI_PLAIN} ${QIQI_CYAN}%s${QIQI_PLAIN} ${QIQI_WHITE}(%s)${QIQI_PLAIN} | %b\n" "$PROJECT_NAME" "$id" "$(project_running_status "$id")"
        printf "    内网: %s | 外网: %s\n" "$local_url" "$public_url"
    done
}

select_project_from_ids() {
    local prompt="$1"
    shift
    local ids=("$@")
    local i choice id
    if [ "${#ids[@]}" -eq 0 ]; then
        yellow "没有可选择的项目。"
        return 1
    fi

    qiqi_section "$prompt"
    i=1
    for id in "${ids[@]}"; do
        load_project_meta "$id"
        printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} %s ${QIQI_WHITE}(%s)${QIQI_PLAIN}\n" "$i" "$PROJECT_NAME" "$id"
        i=$((i + 1))
    done
    printf "  ${QIQI_GREEN}[ 0 ]${QIQI_PLAIN} ${QIQI_WHITE}返回${QIQI_PLAIN}\n"
    echo
    readp "  请输入选项数字 → " choice
    [ "$choice" = "0" ] && return 1
    case "$choice" in ''|*[!0-9]*) red "无效选项。"; return 1 ;; esac
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#ids[@]}" ]; then
        red "无效选项。"
        return 1
    fi
    SELECTED_PROJECT_ID="${ids[$((choice - 1))]}"
    return 0
}

install_or_start_project() {
    local id="$1" source_path target_path local_url public_url
    source_path="$(source_project_path "$id")"
    target_path="$(app_project_path "$id")"

    if ! project_files_exist "$id"; then
        if ! project_has_template "$id"; then
            red "未找到内置模板: $source_path/docker-compose.yml"
            muted "自定义项目请先准备 $target_path/docker-compose.yml。"
            return 1
        fi
        copy_builtin_project_to_app "$id" keep || return 1
    fi

    ensure_project_conf_file "$id" >/dev/null
    confirm_no_placeholder_or_continue "$target_path" || {
        yellow "已取消启动。"
        return 1
    }

    compose_cmd_available || {
        red "未检测到 docker compose。"
        return 1
    }

    pink ">>> 正在拉取 $id 镜像"
    compose_run "$target_path" pull || return 1
    record_project_image_versions "$id"

    pink ">>> 正在启动 $id"
    compose_run "$target_path" up -d || return 1
    record_project_image_versions "$id"
    local_url="$(project_local_url "$id")"
    public_url="$(project_public_url "$id")"
    green "项目已启动: $id"
    green "内网地址: $local_url"
    [ "$public_url" != "未配置" ] && green "外网地址: $public_url"
}

stop_project() {
    local id="$1"
    project_files_exist "$id" || {
        red "项目尚未安装: $id"
        return 1
    }
    pink ">>> 正在停止 $id"
    compose_run "$(app_project_path "$id")" stop
}

restart_project() {
    local id="$1" path
    project_files_exist "$id" || {
        red "项目尚未安装: $id"
        return 1
    }
    path="$(app_project_path "$id")"
    confirm_no_placeholder_or_continue "$path" || {
        yellow "已取消启动。"
        return 1
    }
    pink ">>> 正在启动/重启 $id"
    compose_run "$path" up -d
}

update_project() {
    local id="$1" path
    project_files_exist "$id" || {
        red "项目尚未安装: $id"
        return 1
    }
    path="$(app_project_path "$id")"
    backup_project_dir "$id" || return 1
    pink ">>> 正在拉取镜像并更新 $id"
    compose_run "$path" pull || return 1
    record_project_image_versions "$id"
    compose_run "$path" up -d || return 1
    record_project_image_versions "$id"
    docker image prune -f >/dev/null 2>&1 || true
    green "项目更新完成: $id"
}

delete_project() {
    local id="$1" path delete_volumes delete_dir delete_nginx nginx_dir conf_file
    path="$(app_project_path "$id")"
    project_files_exist "$id" || {
        red "项目尚未安装: $id"
        return 1
    }

    red "即将卸载项目: $id"
    confirm_action "  是否删除 Docker volumes" && delete_volumes=1 || delete_volumes=0
    if [ "$delete_volumes" -eq 1 ]; then
        compose_run "$path" down --rmi all -v
    else
        compose_run "$path" down --rmi all
    fi

    confirm_action "  是否删除项目目录 $path" && delete_dir=1 || delete_dir=0
    if [ "$delete_dir" -eq 1 ]; then
        rm -rf "$path"
        green "项目目录已删除。"
    else
        yellow "已保留项目目录。"
    fi

    confirm_action "  是否同步删除 Nginx 反代配置" && delete_nginx=1 || delete_nginx=0
    if [ "$delete_nginx" -eq 1 ]; then
        nginx_dir="$(detect_nginx_dir)"
        if [ -n "$nginx_dir" ]; then
            conf_file="$(nginx_project_conf "$nginx_dir" "$id")"
            if [ -f "$conf_file" ]; then
                rm -f "$conf_file"
                if [ "$delete_dir" -eq 0 ]; then
                    set_project_conf_value "$id" "PUBLIC_URL" ""
                fi
                green "已删除 Nginx 配置: $conf_file"
                reload_nginx || true
            else
                muted "未找到 Nginx 配置: $conf_file"
            fi
        else
            yellow "未找到 Nginx 目录，跳过。"
        fi
    fi
}

edit_project_conf_interactive() {
    local id="$1" conf_file name desc url image_version health public_url input
    conf_file="$(ensure_project_conf_file "$id")"
    load_project_meta "$id"

    qiqi_section "手动更新 dntool-config/project.conf"
    muted "直接回车会保留当前值。"
    readp "  项目名称 [$PROJECT_NAME] → " input; name="${input:-$PROJECT_NAME}"
    readp "  功能描述 [$DESCRIPTION] → " input; desc="${input:-$DESCRIPTION}"
    readp "  项目地址 [${PROJECT_META_URL:-留空}] → " input; url="${input:-$PROJECT_META_URL}"
    readp "  镜像版本 [${IMAGE_VERSION:-自动记录}] → " input; image_version="${input:-$IMAGE_VERSION}"
    health="${HEALTH_URL:-$(project_local_url "$id")}"
    readp "  健康检查地址 [${health:-留空}] → " input; health="${input:-$health}"
    readp "  外网访问地址 [${PUBLIC_URL:-留空}] → " input; public_url="${input:-$PUBLIC_URL}"

    cat > "$conf_file" << EOF
PROJECT_NAME="$name"
DESCRIPTION="$desc"
PROJECT_URL="$url"
IMAGE_VERSION="$image_version"
HEALTH_URL="$health"
PUBLIC_URL="$public_url"
EOF
    green "已更新: $conf_file"
}

show_custom_project_help() {
    qiqi_section "自定义 Docker 项目"
    muted "请手动上传项目到: $TARGET_BASE_DIR/<项目ID>/docker-compose.yml"
    muted "可选文件: dntool-config/project.conf、dntool-config/<项目ID>.conf 或应用自己的配置文件。"
    muted "上传完成后重新进入 Docker 项目安装菜单，会以 991、992... 显示。"
}

select_custom_project_by_choice() {
    local choice="$1" custom_ids=() index id target_path
    array_from_lines custom_ids "$(list_custom_app_project_ids)"
    index=$((choice - 991))
    if [ "$index" -lt 0 ] || [ "$index" -ge "${#custom_ids[@]}" ]; then
        return 1
    fi
    id="${custom_ids[$index]}"
    target_path="$(app_project_path "$id")"
    ensure_project_conf_file "$id" >/dev/null
    if project_is_installed "$id"; then
        manage_project_loop "$id"
    else
        install_or_start_project "$id"
        pause
    fi
}

install_builtin_project_by_choice() {
    local id="$1"

    if project_is_installed "$id"; then
        manage_project_loop "$id"
        return 0
    fi

    install_or_start_project "$id"
    pause
}

install_menu() {
    local builtin_ids=() custom_ids=() id i choice status menu_no
    while true; do
        array_from_lines builtin_ids "$(list_source_project_ids)"
        array_from_lines custom_ids "$(list_custom_app_project_ids)"
        clear
        qiqi_banner "$PROJECT_TITLE" "$PROJECT_VERSION" "Docker 项目安装" "$PROJECT_URL"
        show_all_installed_summary
        qiqi_section "内置 Docker 项目"
        if [ "${#builtin_ids[@]}" -eq 0 ]; then
            muted "  暂无内置项目模板。"
        else
            i=1
            for id in "${builtin_ids[@]}"; do
                load_project_meta "$id"
                if project_is_installed "$id"; then
                    status="${QIQI_GREEN}已安装 / 进入管理${QIQI_PLAIN}"
                else
                    status="${QIQI_WHITE}未安装 / 选择安装${QIQI_PLAIN}"
                fi
                printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} ${QIQI_WHITE}%s${QIQI_PLAIN} （%b）\n" "$i" "$PROJECT_NAME" "$status"
                i=$((i + 1))
            done
        fi

        qiqi_section "用户自定义项目"
        if [ "${#custom_ids[@]}" -eq 0 ]; then
            muted "  暂无自定义项目。请先上传到 $TARGET_BASE_DIR/<项目ID>/docker-compose.yml"
        else
            i=0
            for id in "${custom_ids[@]}"; do
                menu_no=$((991 + i))
                load_project_meta "$id"
                if project_is_installed "$id"; then
                    status="${QIQI_GREEN}已安装 / 进入管理${QIQI_PLAIN}"
                else
                    status="${QIQI_WHITE}未安装 / 选择安装${QIQI_PLAIN}"
                fi
                printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} ${QIQI_WHITE}%s${QIQI_PLAIN} （%b）\n" "$menu_no" "$PROJECT_NAME" "$status"
                i=$((i + 1))
            done
        fi
        printf "  ${QIQI_GREEN}[ 99 ]${QIQI_PLAIN} 自定义项目上传说明\n"
        printf "  ${QIQI_GREEN}[ 0 ]${QIQI_PLAIN} ${QIQI_WHITE}返回主菜单${QIQI_PLAIN}\n"
        echo
        readp "  请输入选项 → " choice
        case "$choice" in
            0) exit 0 ;;
            99) show_custom_project_help; pause ;;
            ''|*[!0-9]*) red "无效选项。"; sleep 1 ;;
            *)
                if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#builtin_ids[@]}" ] 2>/dev/null; then
                    id="${builtin_ids[$((choice - 1))]}"
                    install_builtin_project_by_choice "$id"
                elif [ "$choice" -ge 991 ] 2>/dev/null && [ "$choice" -le $((990 + ${#custom_ids[@]})) ] 2>/dev/null; then
                    select_custom_project_by_choice "$choice"
                else
                    red "无效选项。"
                    sleep 1
                fi
                ;;
        esac
    done
}

manage_project_loop() {
    local id="$1" choice
    while true; do
        clear
        qiqi_banner "$PROJECT_TITLE" "$PROJECT_VERSION" "Docker 项目管理" "$PROJECT_URL"
        show_project_detail "$id"
        qiqi_section "管理菜单"
        qiqi_menu_item "1" "启动 / 重启项目"
        qiqi_menu_item "2" "停止项目"
        qiqi_menu_item "3" "卸载项目"
        qiqi_menu_item "4" "更新项目（先备份）"
        qiqi_menu_item "5" "Nginx 反代设置"
        qiqi_menu_item "6" "手动更新项目显示配置"
        project_has_template "$id" && qiqi_menu_item "7" "重新安装（覆盖内置项目）"
        qiqi_menu_item "0" "返回"
        echo
        readp "  请输入选项 → " choice
        case "$choice" in
            1) restart_project "$id"; pause ;;
            2) confirm_action "  确认停止 $id" && stop_project "$id"; pause ;;
            3) confirm_action "  确认卸载 $id" && delete_project "$id"; pause; project_is_installed "$id" || return 0 ;;
            4) confirm_action "  确认更新 $id" && update_project "$id"; pause ;;
            5) "$SCRIPT_DIR/nginx_manage.sh" configure "$id"; pause ;;
            6) edit_project_conf_interactive "$id"; pause ;;
            7)
                if project_has_template "$id"; then
                    reinstall_builtin_project "$id" && install_or_start_project "$id"
                else
                    red "当前项目没有内置模板，无法重新安装。"
                fi
                pause
                ;;
            0) return 0 ;;
            *) red "无效选项。"; sleep 1 ;;
        esac
    done
}

manage_menu() {
    local ids=() id i choice
    while true; do
        array_from_lines ids "$(collect_installed_ids)"
        clear
        qiqi_banner "$PROJECT_TITLE" "$PROJECT_VERSION" "Docker 项目管理" "$PROJECT_URL"
        qiqi_section "管理菜单"
        if [ "${#ids[@]}" -eq 0 ]; then
            yellow "  没有已安装项目可管理。"
        else
            i=1
            for id in "${ids[@]}"; do
                load_project_meta "$id"
                printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} ${QIQI_WHITE}%s${QIQI_PLAIN} ${QIQI_WHITE}(%s)${QIQI_PLAIN} | %b\n" "$i" "$PROJECT_NAME" "$id" "$(project_running_status "$id")"
                i=$((i + 1))
            done
        fi
        qiqi_menu_item "0" "返回主菜单"
        echo
        readp "  请输入选项 → " choice
        case "$choice" in
            0) return 0 ;;
            ''|*[!0-9]*) red "无效选项。"; sleep 1 ;;
            *)
                if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#ids[@]}" ] 2>/dev/null; then
                    id="${ids[$((choice - 1))]}"
                    manage_project_loop "$id"
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
    case "${1:-install}" in
        install) install_menu ;;
        manage) manage_menu ;;
        project)
            [ -n "${2:-}" ] || { red "缺少项目ID。"; exit 1; }
            manage_project_loop "$2"
            ;;
        *) install_menu ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
