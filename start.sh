#!/usr/bin/env bash
export LANG=en_US.UTF-8

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common.sh
. "$BASE_DIR/scripts/common.sh"

require_root

environment_gate() {
    local choice
    while true; do
        clear
        qiqi_banner "$PROJECT_TITLE" "$PROJECT_VERSION" "$PROJECT_DESCRIPTION" "$PROJECT_URL"
        show_environment_status
        qiqi_section "运行环境菜单"
        qiqi_menu_item "1" "安装 Docker" "(占位功能，当前只提示)"
        qiqi_menu_item "2" "安装 Nginx" "(占位功能，当前只提示)"
        qiqi_menu_item "3" "进入 DN_Tools 控制台"
        qiqi_menu_item "0" "退出控制台"
        echo
        readp "  请输入选项数字 [0-3] → " choice
        case "$choice" in
            1) install_docker_placeholder; pause ;;
            2) install_nginx_placeholder; pause ;;
            3) return 0 ;;
            0) green "已退出 DN_Tools。"; exit 0 ;;
            *) red "无效选项，请重新输入。"; sleep 1 ;;
        esac
    done
}

main_menu() {
    local choice
    while true; do
        clear
        qiqi_banner "$PROJECT_TITLE" "$PROJECT_VERSION" "$PROJECT_DESCRIPTION" "$PROJECT_URL"
        show_environment_status
        qiqi_section "功能菜单"
        qiqi_menu_item "1" "Docker 项目安装"
        qiqi_menu_item "2" "Docker 项目管理"
        qiqi_menu_item "3" "Nginx 反代设置"
        qiqi_menu_item "0" "退出控制台"
        echo
        readp "  请输入选项数字 [0-3] → " choice
        case "$choice" in
            1)
                if ! docker_available; then
                    red "未检测到 Docker，无法安装或启动 Docker 项目。"
                    install_docker_placeholder
                    pause
                else
                    "$BASE_DIR/scripts/docker_manage.sh" install
                fi
                ;;
            2)
                if ! docker_available; then
                    red "未检测到 Docker，无法管理 Docker 项目。"
                    install_docker_placeholder
                    pause
                else
                    "$BASE_DIR/scripts/docker_manage.sh" manage
                fi
                ;;
            3)
                if ! nginx_available && [ -z "${NGINX_DIR_OVERRIDE:-}" ]; then
                    red "未检测到 Nginx，无法管理反代配置。"
                    install_nginx_placeholder
                    pause
                else
                    "$BASE_DIR/scripts/nginx_manage.sh"
                fi
                ;;
            0)
                green "已退出 DN_Tools。"
                exit 0
                ;;
            *)
                red "无效选项，请重新输入。"
                sleep 1
                ;;
        esac
    done
}

if ! docker_available || { ! nginx_available && [ -z "${NGINX_DIR_OVERRIDE:-}" ]; }; then
    environment_gate
fi

main_menu
