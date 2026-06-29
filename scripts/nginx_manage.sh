#!/usr/bin/env bash
export LANG=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

TEMPLATE_DIR="$NGINX_CONFIG_SOURCE_DIR/templates"
SELECTED_TEMPLATE=""
SELECTED_PROJECT_ID=""

sed_escape() {
    printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

list_templates() {
    local file
    [ -d "$TEMPLATE_DIR" ] || return 0
    for file in "$TEMPLATE_DIR"/*.conf; do
        [ -f "$file" ] || continue
        basename "$file" .conf
    done
}

template_description() {
    case "$1" in
        default) printf '通用 Web 反代' ;;
        ai-stream) printf 'AI 长连接 / 流式输出 / 大文件上传' ;;
        strict) printf '更严格安全头与 TLS 设置' ;;
        *) printf '自定义模板' ;;
    esac
}

select_template() {
    local preferred="$1" templates=() name i choice
    while IFS= read -r name; do
        [ -n "$name" ] && templates+=("$name")
    done < <(list_templates)

    if [ "${#templates[@]}" -eq 0 ]; then
        red "未找到 Nginx 模板: $TEMPLATE_DIR/*.conf"
        return 1
    fi

    qiqi_section "选择反代模板"
    i=1
    for name in "${templates[@]}"; do
        if [ "$name" = "$preferred" ]; then
            printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} %s ${QIQI_GRAY}(%s, 默认)${QIQI_PLAIN}\n" "$i" "$name" "$(template_description "$name")"
        else
            printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} %s ${QIQI_GRAY}(%s)${QIQI_PLAIN}\n" "$i" "$name" "$(template_description "$name")"
        fi
        i=$((i + 1))
    done
    printf "  ${QIQI_GRAY}[ 0 ]${QIQI_PLAIN} 返回\n"
    echo
    readp "  请输入选项数字 → " choice
    if [ -z "$choice" ] && [ -n "$preferred" ]; then
        for name in "${templates[@]}"; do
            if [ "$name" = "$preferred" ]; then
                SELECTED_TEMPLATE="$preferred"
                return 0
            fi
        done
    fi
    [ "$choice" = "0" ] && return 1
    case "$choice" in ''|*[!0-9]*) red "无效选项。"; return 1 ;; esac
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#templates[@]}" ]; then
        red "无效选项。"
        return 1
    fi
    SELECTED_TEMPLATE="${templates[$((choice - 1))]}"
}

select_project_or_custom() {
    local ids=() id i choice
    while IFS= read -r id; do
        [ -n "$id" ] && ids+=("$id")
    done < <(collect_installed_ids)

    qiqi_section "选择反代项目"
    i=1
    for id in "${ids[@]}"; do
        load_project_meta "$id"
        printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} %s ${QIQI_GRAY}(%s)${QIQI_PLAIN}\n" "$i" "$PROJECT_NAME" "$id"
        i=$((i + 1))
    done
    printf "  ${QIQI_GREEN}[ C ]${QIQI_PLAIN} 手动输入自定义反代\n"
    printf "  ${QIQI_GRAY}[ 0 ]${QIQI_PLAIN} 返回\n"
    echo
    readp "  请输入选项 → " choice
    case "$choice" in
        0) return 1 ;;
        C|c)
            readp "  配置文件名 / 项目ID → " SELECTED_PROJECT_ID
            [ -n "$SELECTED_PROJECT_ID" ] || return 1
            reset_project_meta "$SELECTED_PROJECT_ID"
            return 0
            ;;
        ''|*[!0-9]*) red "无效选项。"; return 1 ;;
    esac
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#ids[@]}" ]; then
        red "无效选项。"
        return 1
    fi
    SELECTED_PROJECT_ID="${ids[$((choice - 1))]}"
    load_project_meta "$SELECTED_PROJECT_ID"
}

render_template() {
    local template_file="$1" output_file="$2" server_name="$3" listen_port="$4"
    local upstream_host="$5" upstream_port="$6" ssl_cert="$7" ssl_key="$8" body_size="$9"
    sed \
        -e "s|{{SERVER_NAME}}|$(sed_escape "$server_name")|g" \
        -e "s|{{LISTEN_PORT}}|$(sed_escape "$listen_port")|g" \
        -e "s|{{UPSTREAM_HOST}}|$(sed_escape "$upstream_host")|g" \
        -e "s|{{UPSTREAM_PORT}}|$(sed_escape "$upstream_port")|g" \
        -e "s|{{SSL_CERT}}|$(sed_escape "$ssl_cert")|g" \
        -e "s|{{SSL_KEY}}|$(sed_escape "$ssl_key")|g" \
        -e "s|{{CLIENT_MAX_BODY_SIZE}}|$(sed_escape "$body_size")|g" \
        "$template_file" > "$output_file"
}

extract_current_value() {
    local conf="$1" key="$2"
    [ -f "$conf" ] || return 0
    case "$key" in
        domain) awk '/server_name/ {gsub(";", "", $2); print $2; exit}' "$conf" ;;
        listen) awk '/listen[[:space:]]+[0-9]+/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+/) {gsub(";", "", $i); print $i; exit}}' "$conf" ;;
        upstream_host) sed -n 's/.*proxy_pass http:\/\/\([^:;]*\):[0-9][0-9]*.*/\1/p' "$conf" | sed -n '1p' ;;
        upstream_port) sed -n 's/.*proxy_pass http:\/\/[^:;]*:\([0-9][0-9]*\).*/\1/p' "$conf" | sed -n '1p' ;;
        cert) awk '/ssl_certificate[[:space:]]+/ && $1 == "ssl_certificate" {gsub(";", "", $2); print $2; exit}' "$conf" ;;
        key) awk '/ssl_certificate_key/ {gsub(";", "", $2); print $2; exit}' "$conf" ;;
        body) awk '/client_max_body_size/ {gsub(";", "", $2); print $2; exit}' "$conf" ;;
    esac
}

public_url_from_domain() {
    local domain="$1" listen_port="$2"
    if [ "$listen_port" = "443" ] || [ -z "$listen_port" ]; then
        printf 'https://%s' "$domain"
    else
        printf 'https://%s:%s' "$domain" "$listen_port"
    fi
}

backup_nginx_conf_to_project() {
    local id="$1" conf_file="$2" backup_base backup_dir
    if project_is_installed "$id"; then
        backup_base="$(app_project_path "$id")"
    else
        backup_base="$(project_runtime_path "$id")"
    fi
    [ -d "$backup_base" ] || return 0
    backup_dir="$backup_base/nginx-config"
    mkdir -p "$backup_dir"
    cp "$conf_file" "$backup_dir/$id.conf"
    green "已备份反代配置到: $backup_dir/$id.conf"
}

record_nginx_project_meta() {
    local id="$1" template="$2" public_url="$3" app_path
    app_path="$(app_project_path "$id")"
    if project_is_installed "$id" || [ -d "$app_path" ]; then
        set_project_conf_value "$id" "NGINX_TEMPLATE" "$template"
        set_project_conf_value "$id" "PUBLIC_URL" "$public_url"
    else
        muted "项目未安装到 $app_path，跳过 project.conf 回写。"
    fi
}

clear_nginx_project_meta() {
    local id="$1" app_path
    app_path="$(app_project_path "$id")"
    if project_is_installed "$id" || [ -d "$app_path" ]; then
        set_project_conf_value "$id" "PUBLIC_URL" ""
    fi
}

delete_project_reverse_proxy() {
    local id="$1" nginx_dir conf_file
    nginx_dir="$(detect_nginx_dir)"
    [ -n "$nginx_dir" ] || {
        red "未找到 Nginx 配置目录。"
        return 1
    }
    conf_file="$(nginx_project_conf "$nginx_dir" "$id")"
    if [ ! -f "$conf_file" ]; then
        yellow "未找到配置文件: $conf_file"
        return 0
    fi
    confirm_action "  确认删除 $conf_file" || return 0
    rm -f "$conf_file"
    clear_nginx_project_meta "$id"
    green "已删除: $conf_file"
    reload_nginx
}

configure_reverse_proxy() {
    local id="${1:-}" nginx_dir conf_dir current_conf template_file tmp_file out_file default_port
    local old_domain old_listen old_host old_port old_cert old_key old_body
    local action domain upstream_host upstream_port listen_port ssl_cert ssl_key body_size public_url confirm

    nginx_dir="$(detect_nginx_dir)"
    if [ -z "$nginx_dir" ]; then
        readp "  自动搜寻 Nginx 目录失败，请输入配置目录（如 /etc/nginx）→ " nginx_dir
    fi
    [ -n "$nginx_dir" ] || return 1

    if [ -z "$id" ]; then
        select_project_or_custom || return 1
        id="$SELECTED_PROJECT_ID"
    else
        load_project_meta "$id"
    fi

    current_conf="$(nginx_project_conf "$nginx_dir" "$id")"
    if [ -f "$current_conf" ]; then
        qiqi_section "当前反代配置"
        sed -n '1,220p' "$current_conf"
        echo
        qiqi_menu_item "1" "更新配置"
        qiqi_menu_item "2" "删除配置"
        printf "  ${QIQI_GRAY}[ 0 ]${QIQI_PLAIN}  返回\n"
        readp "  请输入选项 → " action
        case "$action" in
            1) ;;
            2) delete_project_reverse_proxy "$id"; return $? ;;
            0) return 0 ;;
            *) red "无效选项。"; return 1 ;;
        esac
    fi

    load_project_meta "$id"
    select_template "${NGINX_TEMPLATE:-default}" || return 1
    template_file="$TEMPLATE_DIR/$SELECTED_TEMPLATE.conf"
    [ -f "$template_file" ] || {
        red "模板不存在: $template_file"
        return 1
    }

    old_domain="$(extract_current_value "$current_conf" domain)"
    old_listen="$(extract_current_value "$current_conf" listen)"
    old_host="$(extract_current_value "$current_conf" upstream_host)"
    old_port="$(extract_current_value "$current_conf" upstream_port)"
    old_cert="$(extract_current_value "$current_conf" cert)"
    old_key="$(extract_current_value "$current_conf" key)"
    old_body="$(extract_current_value "$current_conf" body)"
    default_port="${ACCESS_PORT:-$(infer_compose_port "$(project_runtime_path "$id")/docker-compose.yml")}"

    qiqi_section "填写反代参数"
    muted "直接回车会使用括号内默认值。"
    readp "  绑定域名 [${old_domain:-your-domain.com}] → " domain
    domain="${domain:-${old_domain:-your-domain.com}}"
    readp "  上游主机 [${old_host:-${ACCESS_HOST:-127.0.0.1}}] → " upstream_host
    upstream_host="${upstream_host:-${old_host:-${ACCESS_HOST:-127.0.0.1}}}"
    readp "  上游端口 [${old_port:-${default_port:-3000}}] → " upstream_port
    upstream_port="${upstream_port:-${old_port:-${default_port:-3000}}}"
    readp "  HTTPS 监听端口 [${old_listen:-443}] → " listen_port
    listen_port="${listen_port:-${old_listen:-443}}"
    readp "  SSL 证书路径 [${old_cert:-/path/to/fullchain.pem}] → " ssl_cert
    ssl_cert="${ssl_cert:-${old_cert:-/path/to/fullchain.pem}}"
    readp "  SSL 私钥路径 [${old_key:-/path/to/privkey.pem}] → " ssl_key
    ssl_key="${ssl_key:-${old_key:-/path/to/privkey.pem}}"
    readp "  上传大小限制 [${old_body:-50m}] → " body_size
    body_size="${body_size:-${old_body:-50m}}"

    tmp_file="$(mktemp)"
    render_template "$template_file" "$tmp_file" "$domain" "$listen_port" "$upstream_host" "$upstream_port" "$ssl_cert" "$ssl_key" "$body_size"

    qiqi_section "配置预览"
    sed -n '1,240p' "$tmp_file"
    echo
    readp "  确认写入 $nginx_dir/conf.d/$id.conf ? [y/N] → " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        rm -f "$tmp_file"
        yellow "已取消写入。"
        return 0
    fi

    conf_dir="$nginx_dir/conf.d"
    mkdir -p "$conf_dir"
    out_file="$conf_dir/$id.conf"
    cp "$tmp_file" "$out_file"
    rm -f "$tmp_file"

    public_url="$(public_url_from_domain "$domain" "$listen_port")"
    record_nginx_project_meta "$id" "$SELECTED_TEMPLATE" "$public_url"
    backup_nginx_conf_to_project "$id" "$out_file"
    green "配置已写入: $out_file"
    green "公网地址已记录: $public_url"
    ensure_nginx_include "$nginx_dir" || return 1
    reload_nginx
}

delete_reverse_proxy_menu() {
    local nginx_dir conf_files=() file i choice id
    nginx_dir="$(detect_nginx_dir)"
    [ -n "$nginx_dir" ] || {
        red "未找到 Nginx 配置目录。"
        return 1
    }
    for file in "$nginx_dir"/conf.d/*.conf; do
        [ -f "$file" ] && conf_files+=("$file")
    done
    if [ "${#conf_files[@]}" -eq 0 ]; then
        yellow "暂无可删除的 conf.d/*.conf。"
        return 0
    fi

    qiqi_section "选择要删除的反代配置"
    i=1
    for file in "${conf_files[@]}"; do
        printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} %s\n" "$i" "$file"
        i=$((i + 1))
    done
    printf "  ${QIQI_GRAY}[ 0 ]${QIQI_PLAIN} 返回\n"
    readp "  请输入选项数字 → " choice
    [ "$choice" = "0" ] && return 0
    case "$choice" in ''|*[!0-9]*) red "无效选项。"; return 1 ;; esac
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#conf_files[@]}" ]; then
        red "无效选项。"
        return 1
    fi
    file="${conf_files[$((choice - 1))]}"
    id="$(basename "$file" .conf)"
    delete_project_reverse_proxy "$id"
}

show_nginx_status() {
    local nginx_dir file found=0
    nginx_dir="$(detect_nginx_dir)"
    qiqi_section "Nginx 配置状态"
    if [ -z "$nginx_dir" ]; then
        red "未找到 Nginx 配置目录。"
        return 0
    fi
    green "  Nginx 目录: $nginx_dir"
    if [ -f "$nginx_dir/nginx.conf" ]; then
        green "  主配置: $nginx_dir/nginx.conf"
    else
        red "  主配置不存在: $nginx_dir/nginx.conf"
    fi
    echo
    for file in "$nginx_dir"/conf.d/*.conf; do
        [ -f "$file" ] || continue
        found=1
        printf "  ${QIQI_GREEN}⬥${QIQI_PLAIN} %s\n" "$file"
    done
    [ "$found" -eq 0 ] && muted "  暂无 conf.d/*.conf"
}

nginx_manage_main() {
    local choice
    require_root
    while true; do
        clear
        qiqi_banner "$PROJECT_TITLE" "$PROJECT_VERSION" "Nginx 反代设置" "$PROJECT_URL"
        show_nginx_status
        qiqi_section "Nginx 管理菜单"
        qiqi_menu_item "1" "新增 / 修改反代配置"
        qiqi_menu_item "2" "删除反代配置"
        qiqi_menu_item "3" "测试并重载 Nginx"
        qiqi_menu_item "4" "刷新状态"
        printf "  ${QIQI_GRAY}[ 0 ]${QIQI_PLAIN}  返回主菜单\n"
        echo
        readp "  请输入选项 → " choice
        case "$choice" in
            1) configure_reverse_proxy; pause ;;
            2) delete_reverse_proxy_menu; pause ;;
            3) reload_nginx; pause ;;
            4) ;;
            0) exit 0 ;;
            *) red "无效选项。"; sleep 1 ;;
        esac
    done
}

main() {
    case "${1:-menu}" in
        configure)
            require_root
            configure_reverse_proxy "${2:-}"
            ;;
        delete)
            require_root
            if [ -n "${2:-}" ]; then
                delete_project_reverse_proxy "$2"
            else
                delete_reverse_proxy_menu
            fi
            ;;
        menu|*) nginx_manage_main ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
