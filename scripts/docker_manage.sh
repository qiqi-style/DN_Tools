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
    images="$(project_images "$compose_file")"
    [ -n "$containers" ] || containers="未识别"
    [ -n "$images" ] || images="未识别"

    qiqi_section "项目详情"
    printf "  ${QIQI_GREEN}项目名称${QIQI_PLAIN}: %s ${QIQI_GRAY}(%s)${QIQI_PLAIN}\n" "$PROJECT_NAME" "$id"
    printf "  ${QIQI_GREEN}功能说明${QIQI_PLAIN}: %s\n" "$DESCRIPTION"
    printf "  ${QIQI_GREEN}项目地址${QIQI_PLAIN}: %s\n" "${PROJECT_META_URL:-未配置}"
    printf "  ${QIQI_GREEN}运行目录${QIQI_PLAIN}: %s\n" "$path"
    printf "  ${QIQI_GREEN}容器名称${QIQI_PLAIN}: %s\n" "$containers"
    printf "  ${QIQI_GREEN}镜像版本${QIQI_PLAIN}: %s\n" "$images"
    printf "  ${QIQI_GREEN}当前状态${QIQI_PLAIN}: %b\n" "$(project_running_status "$id")"
    printf "  ${QIQI_GREEN}内网地址${QIQI_PLAIN}: %s %b\n" "$local_url" "$(check_url "$health_url")"
    printf "  ${QIQI_GREEN}外网地址${QIQI_PLAIN}: %s %b\n" "$public_url" "$(check_url "$public_url")"
    printf "  ${QIQI_GREEN}最新版本${QIQI_PLAIN}: 运行更新时通过 docker compose pull 获取\n"
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
        printf "  ${QIQI_GREEN}⬥${QIQI_PLAIN} ${QIQI_CYAN}%s${QIQI_PLAIN} ${QIQI_GRAY}(%s)${QIQI_PLAIN} | %b\n" "$PROJECT_NAME" "$id" "$(project_running_status "$id")"
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
        printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} %s ${QIQI_GRAY}(%s)${QIQI_PLAIN}\n" "$i" "$PROJECT_NAME" "$id"
        i=$((i + 1))
    done
    printf "  ${QIQI_GRAY}[ 0 ]${QIQI_PLAIN} 返回\n"
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

    if ! project_is_installed "$id"; then
        if ! project_has_template "$id"; then
            red "未找到内置模板: $source_path/docker-compose.yml"
            muted "自定义项目请先准备 $target_path/docker-compose.yml。"
            return 1
        fi
        mkdir -p "$TARGET_BASE_DIR"
        mkdir -p "$target_path"
        pink ">>> 正在复制模板到 $target_path"
        cp -a "$source_path/." "$target_path/"
    fi

    [ -f "$target_path/project.conf" ] || write_project_conf_defaults "$id" "$target_path/project.conf"
    prepare_env_file "$target_path"
    confirm_no_placeholder_or_continue "$target_path" || {
        yellow "已取消启动。"
        return 1
    }

    compose_cmd_available || {
        red "未检测到 docker compose。"
        return 1
    }

    pink ">>> 正在启动 $id"
    compose_run "$target_path" up -d || return 1
    local_url="$(project_local_url "$id")"
    public_url="$(project_public_url "$id")"
    green "项目已启动: $id"
    green "内网地址: $local_url"
    [ "$public_url" != "未配置" ] && green "外网地址: $public_url"
}

stop_project() {
    local id="$1"
    project_is_installed "$id" || {
        red "项目尚未安装: $id"
        return 1
    }
    pink ">>> 正在停止 $id"
    compose_run "$(app_project_path "$id")" stop
}

restart_project() {
    local id="$1" path
    project_is_installed "$id" || {
        red "项目尚未安装: $id"
        return 1
    }
    path="$(app_project_path "$id")"
    prepare_env_file "$path"
    confirm_no_placeholder_or_continue "$path" || {
        yellow "已取消启动。"
        return 1
    }
    pink ">>> 正在启动/重启 $id"
    compose_run "$path" up -d
}

update_project() {
    local id="$1" path
    project_is_installed "$id" || {
        red "项目尚未安装: $id"
        return 1
    }
    path="$(app_project_path "$id")"
    backup_project_dir "$id" || return 1
    pink ">>> 正在拉取镜像并更新 $id"
    compose_run "$path" pull || return 1
    compose_run "$path" up -d || return 1
    docker image prune -f >/dev/null 2>&1 || true
    green "项目更新完成: $id"
}

delete_project() {
    local id="$1" path delete_volumes delete_dir delete_nginx nginx_dir conf_file
    path="$(app_project_path "$id")"
    project_is_installed "$id" || {
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
    local id="$1" conf_file name desc url scheme host port path health template public_url input
    conf_file="$(project_conf_file_for_write "$id")"
    [ -f "$conf_file" ] || write_project_conf_defaults "$id" "$conf_file"
    load_project_meta "$id"

    qiqi_section "手动更新 project.conf"
    muted "直接回车会保留当前值。"
    readp "  项目名称 [$PROJECT_NAME] → " input; name="${input:-$PROJECT_NAME}"
    readp "  功能描述 [$DESCRIPTION] → " input; desc="${input:-$DESCRIPTION}"
    readp "  项目地址 [${PROJECT_META_URL:-留空}] → " input; url="${input:-$PROJECT_META_URL}"
    readp "  内网协议 [${ACCESS_SCHEME:-http}] → " input; scheme="${input:-${ACCESS_SCHEME:-http}}"
    readp "  内网主机 [${ACCESS_HOST:-127.0.0.1}] → " input; host="${input:-${ACCESS_HOST:-127.0.0.1}}"
    readp "  内网端口 [${ACCESS_PORT:-自动识别}] → " input; port="${input:-$ACCESS_PORT}"
    readp "  访问路径 [${ACCESS_PATH:-/}] → " input; path="${input:-${ACCESS_PATH:-/}}"
    health="${HEALTH_URL:-${scheme}://${host}:${port}${path}}"
    readp "  健康检查地址 [${health:-留空}] → " input; health="${input:-$health}"
    readp "  默认 Nginx 模板 [${NGINX_TEMPLATE:-default}] → " input; template="${input:-${NGINX_TEMPLATE:-default}}"
    readp "  外网访问地址 [${PUBLIC_URL:-留空}] → " input; public_url="${input:-$PUBLIC_URL}"

    cat > "$conf_file" << EOF
PROJECT_NAME="$name"
DESCRIPTION="$desc"
PROJECT_URL="$url"
ACCESS_SCHEME="$scheme"
ACCESS_HOST="$host"
ACCESS_PORT="$port"
ACCESS_PATH="$path"
HEALTH_URL="$health"
NGINX_TEMPLATE="$template"
PUBLIC_URL="$public_url"
EOF
    green "已更新: $conf_file"
}

custom_install_project() {
    local id target_path
    qiqi_section "自定义 Docker 项目"
    muted "请准备目录: $TARGET_BASE_DIR/<项目ID>/docker-compose.yml"
    muted "可选文件: project.conf、.env、Nginx 或应用自己的配置文件。"
    echo
    readp "  输入项目ID开始管理，或直接回车返回 → " id
    [ -n "$id" ] || return 0
    case "$id" in */*|*..*) red "项目ID 不允许包含 / 或 .."; return 1 ;; esac
    target_path="$(app_project_path "$id")"
    if [ ! -f "$target_path/docker-compose.yml" ]; then
        red "未找到: $target_path/docker-compose.yml"
        return 1
    fi
    [ -f "$target_path/project.conf" ] || write_project_conf_defaults "$id" "$target_path/project.conf"
    manage_project_loop "$id"
}

install_menu() {
    local ids=() id i choice status label
    while true; do
        array_from_lines ids "$(list_project_ids)"
        clear
        qiqi_banner "$PROJECT_TITLE" "$PROJECT_VERSION" "Docker 项目安装" "$PROJECT_URL"
        show_all_installed_summary
        qiqi_section "可安装 / 可管理项目"
        if [ "${#ids[@]}" -eq 0 ]; then
            muted "  暂无项目模板。"
        else
            i=1
            for id in "${ids[@]}"; do
                load_project_meta "$id"
                if project_is_installed "$id"; then
                    status="${QIQI_GREEN}已安装${QIQI_PLAIN}"
                    label="进入管理"
                else
                    status="${QIQI_GRAY}未安装${QIQI_PLAIN}"
                    label="安装"
                fi
                printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} %s ${QIQI_GRAY}(%s)${QIQI_PLAIN} - %b / %s\n" "$i" "$PROJECT_NAME" "$id" "$status" "$label"
                i=$((i + 1))
            done
        fi
        printf "  ${QIQI_GREEN}[ 99 ]${QIQI_PLAIN} 自定义安装说明 / 管理 /app 项目\n"
        printf "  ${QIQI_GRAY}[ 0 ]${QIQI_PLAIN} 返回主菜单\n"
        echo
        readp "  请输入选项 → " choice
        case "$choice" in
            0) exit 0 ;;
            99) custom_install_project; pause ;;
            ''|*[!0-9]*) red "无效选项。"; sleep 1 ;;
            *)
                if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#ids[@]}" ] 2>/dev/null; then
                    id="${ids[$((choice - 1))]}"
                    if project_is_installed "$id"; then
                        manage_project_loop "$id"
                    else
                        install_or_start_project "$id"
                        pause
                    fi
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
        qiqi_menu_item "6" "手动更新 project.conf"
        printf "  ${QIQI_GRAY}[ 0 ]${QIQI_PLAIN}  返回\n"
        echo
        readp "  请输入选项 → " choice
        case "$choice" in
            1) restart_project "$id"; pause ;;
            2) confirm_action "  确认停止 $id" && stop_project "$id"; pause ;;
            3) confirm_action "  确认卸载 $id" && delete_project "$id"; pause; project_is_installed "$id" || return 0 ;;
            4) confirm_action "  确认更新 $id" && update_project "$id"; pause ;;
            5) "$SCRIPT_DIR/nginx_manage.sh" configure "$id"; pause ;;
            6) edit_project_conf_interactive "$id"; pause ;;
            0) return 0 ;;
            *) red "无效选项。"; sleep 1 ;;
        esac
    done
}

manage_menu() {
    local ids=()
    array_from_lines ids "$(collect_installed_ids)"
    if [ "${#ids[@]}" -eq 0 ]; then
        yellow "没有已安装项目可管理。"
        return 0
    fi
    select_project_from_ids "选择要管理的项目" "${ids[@]}" && manage_project_loop "$SELECTED_PROJECT_ID"
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
