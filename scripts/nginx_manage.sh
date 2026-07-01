#!/usr/bin/env bash
export LANG=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

TEMPLATE_DIR="$NGINX_CONFIG_SOURCE_DIR/templates"
SELECTED_TEMPLATE=""
SELECTED_PROJECT_ID=""
HTTP_REDIRECT_ENABLED=0

sed_escape() {
    printf '%s' "$1" | sed 's/[&|#]/\\&/g'
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
            printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} %s ${QIQI_WHITE}(%s, 默认)${QIQI_PLAIN}\n" "$i" "$name" "$(template_description "$name")"
        else
            printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} %s ${QIQI_WHITE}(%s)${QIQI_PLAIN}\n" "$i" "$name" "$(template_description "$name")"
        fi
        i=$((i + 1))
    done
    printf "  ${QIQI_GREEN}[ 99 ]${QIQI_PLAIN} ${QIQI_WHITE}手动编辑配置（vim）${QIQI_PLAIN}\n"
    printf "  ${QIQI_GREEN}[ 0 ]${QIQI_PLAIN} ${QIQI_WHITE}返回${QIQI_PLAIN}\n"
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
    if [ "$choice" = "99" ]; then
        SELECTED_TEMPLATE="__manual__"
        return 0
    fi
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
        printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN} %s ${QIQI_WHITE}(%s)${QIQI_PLAIN}\n" "$i" "$PROJECT_NAME" "$id"
        i=$((i + 1))
    done
    printf "  ${QIQI_GREEN}[ C ]${QIQI_PLAIN} 手动输入自定义反代\n"
    printf "  ${QIQI_GREEN}[ 0 ]${QIQI_PLAIN} ${QIQI_WHITE}返回${QIQI_PLAIN}\n"
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
    local http_redirect="${10:-0}"
    sed \
        -e "s|{{SERVER_NAME}}|$(sed_escape "$server_name")|g" \
        -e "s|{{LISTEN_PORT}}|$(sed_escape "$listen_port")|g" \
        -e "s|{{UPSTREAM_HOST}}|$(sed_escape "$upstream_host")|g" \
        -e "s|{{UPSTREAM_PORT}}|$(sed_escape "$upstream_port")|g" \
        -e "s|{{SSL_CERT}}|$(sed_escape "$ssl_cert")|g" \
        -e "s|{{SSL_KEY}}|$(sed_escape "$ssl_key")|g" \
        -e "s|{{CLIENT_MAX_BODY_SIZE}}|$(sed_escape "$body_size")|g" \
        "$template_file" > "$output_file"
    apply_http_redirect_policy "$output_file" "$server_name" "$http_redirect"
}

render_project_nginx_conf() {
    local template_file="$1" output_file="$2" server_name="$3" listen_port="$4"
    local ssl_cert="$5" ssl_key="$6" body_size="$7" http_redirect="${8:-0}"
    sed -E \
        -e "s#server_name[[:space:]]+[^;]+;#server_name $(sed_escape "$server_name");#g" \
        -e "s#listen[[:space:]]+[0-9]+([[:space:]][^;]*(ssl|quic)[^;]*;)#listen $(sed_escape "$listen_port")\\1#g" \
        -e "s#ssl_certificate[[:space:]]+[^;]+;#ssl_certificate      $(sed_escape "$ssl_cert");#g" \
        -e "s#ssl_certificate_key[[:space:]]+[^;]+;#ssl_certificate_key  $(sed_escape "$ssl_key");#g" \
        -e "s#client_max_body_size[[:space:]]+[^;]+;#client_max_body_size $(sed_escape "$body_size");#g" \
        "$template_file" > "$output_file"
    apply_http_redirect_policy "$output_file" "$server_name" "$http_redirect"
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

public_url_from_conf() {
    local conf="$1" domain listen_port
    domain="$(extract_current_value "$conf" domain)"
    listen_port="$(extract_current_value "$conf" listen)"
    [ -n "$domain" ] || return 1
    public_url_from_domain "$domain" "$listen_port"
}

nginx_conf_has_http_redirect() {
    local conf="$1"
    [ -f "$conf" ] || return 1
    grep -Eq 'listen[[:space:]]+80([[:space:];]|$)' "$conf" &&
        grep -Fq 'return 301 https://$host$request_uri;' "$conf"
}

choose_http_redirect() {
    local listen_port="$1" defaults_conf="$2" answer default_label
    HTTP_REDIRECT_ENABLED=0
    if [ "$listen_port" != "443" ]; then
        muted "HTTPS 监听端口不是 443，已不生成 80 端口跳转到 443 的配置。"
        return 0
    fi

    if [ -n "$defaults_conf" ] && nginx_conf_has_http_redirect "$defaults_conf"; then
        default_label="Y/n"
    else
        default_label="y/N"
    fi

    readp "  是否启用 80 端口 HTTP 自动跳转到 HTTPS 443 ? [$default_label] → " answer
    if [ "$default_label" = "Y/n" ]; then
        case "$answer" in [Nn]) HTTP_REDIRECT_ENABLED=0 ;; *) HTTP_REDIRECT_ENABLED=1 ;; esac
    else
        case "$answer" in [Yy]) HTTP_REDIRECT_ENABLED=1 ;; *) HTTP_REDIRECT_ENABLED=0 ;; esac
    fi
}

append_http_redirect_block() {
    local output_file="$1" server_name="$2"
    {
        echo
        echo "# HTTP 80 端口跳转到 HTTPS 443"
        echo "server {"
        echo "    # 监听普通 HTTP 80 端口"
        echo "    listen 80;"
        echo "    # 使用与 HTTPS 服务相同的域名"
        printf '    server_name %s;\n' "$server_name"
        echo "    # 永久重定向到 HTTPS，并保留原始路径和查询参数"
        printf '    return 301 https://$host$request_uri;\n'
        echo "}"
    } >> "$output_file"
}

strip_standard_http_redirect_block() {
    local input_file="$1" output_file="$2"
    awk '
        function reset_block() {
            block = ""
            depth = 0
            in_server = 0
            has_listen80 = 0
            has_https_redirect = 0
        }
        BEGIN { reset_block() }
        /^[[:space:]]*server[[:space:]]*\{/ && !in_server {
            in_server = 1
            depth = 1
            block = $0 ORS
            if ($0 ~ /listen[[:space:]]+80([[:space:];]|$)/) has_listen80 = 1
            if ($0 ~ /return[[:space:]]+301[[:space:]]+https:\/\/\$host\$request_uri/) has_https_redirect = 1
            next
        }
        in_server {
            block = block $0 ORS
            if ($0 ~ /listen[[:space:]]+80([[:space:];]|$)/) has_listen80 = 1
            if ($0 ~ /return[[:space:]]+301[[:space:]]+https:\/\/\$host\$request_uri/) has_https_redirect = 1
            for (i = 1; i <= length($0); i++) {
                char = substr($0, i, 1)
                if (char == "{") depth++
                if (char == "}") depth--
            }
            if (depth <= 0) {
                if (!(has_listen80 && has_https_redirect)) printf "%s", block
                reset_block()
            }
            next
        }
        { print }
        END {
            if (in_server && depth > 0) printf "%s", block
        }
    ' "$input_file" > "$output_file"
}

apply_http_redirect_policy() {
    local conf_file="$1" server_name="$2" enabled="$3" tmp clean_tmp
    tmp="$(mktemp)"
    strip_standard_http_redirect_block "$conf_file" "$tmp" || {
        rm -f "$tmp"
        return 1
    }
    clean_tmp="$(mktemp)"
    sed -E '/^[[:space:]]*#[[:space:]]*(HTTP[[:space:]]*)?80.*(443|HTTPS)/d' "$tmp" > "$clean_tmp"
    rm -f "$tmp"
    mv "$clean_tmp" "$conf_file"
    if [ "$enabled" = "1" ]; then
        append_http_redirect_block "$conf_file" "$server_name"
    fi
}

edit_conf_with_vim() {
    local conf_file="$1"
    if ! command_exists vim; then
        red "错误: 未检测到 vim，无法进入手动编辑。"
        return 1
    fi
    vim "$conf_file"
}

confirm_tmp_conf_write() {
    local tmp_file="$1" target_file="$2" confirm
    while true; do
        qiqi_section "配置预览"
        sed -n '1,260p' "$tmp_file"
        echo
        readp "  确认写入 $target_file ? [y 写入 / n 取消 / e 手动 vim 编辑] → " confirm
        case "$confirm" in
            [Yy]) return 0 ;;
            [Nn]|"") yellow "已取消写入。"; return 1 ;;
            [Ee]) edit_conf_with_vim "$tmp_file" || return 1 ;;
            *) red "无效选项，请输入 y、n 或 e。" ;;
        esac
    done
}

create_manual_nginx_conf_seed() {
    local id="$1" output_file="$2" default_port upstream_host
    default_port="${ACCESS_PORT:-$(infer_compose_port "$(project_runtime_path "$id")/docker-compose.yml")}"
    upstream_host="${ACCESS_HOST:-127.0.0.1}"
    {
        echo "# DN_Tools 手动 Nginx 反向代理配置"
        echo "# 请把 your-domain.com、证书路径、上游端口改成你的真实配置。"
        echo "server {"
        echo "    # HTTPS 监听端口；ssl 表示启用 TLS"
        echo "    listen 443 ssl;"
        echo "    # 访问域名"
        echo "    server_name your-domain.com;"
        echo
        echo "    # SSL 证书文件路径"
        echo "    ssl_certificate      /path/to/fullchain.pem;"
        echo "    # SSL 私钥文件路径"
        echo "    ssl_certificate_key  /path/to/privkey.pem;"
        echo
        echo "    # 客户端上传大小限制，默认 50m"
        echo "    client_max_body_size 50m;"
        echo
        echo "    # 将页面中的 HTTP 资源自动升级为 HTTPS"
        echo '    add_header Content-Security-Policy "upgrade-insecure-requests" always;'
        echo
        echo "    location / {"
        echo "        # Docker 服务的本机访问地址"
        printf '        proxy_pass http://%s:%s;\n' "$upstream_host" "${default_port:-3000}"
        echo
        echo "        # 使用 HTTP/1.1，兼容 WebSocket 和流式响应"
        echo "        proxy_http_version 1.1;"
        echo "        # 保留原始访问域名"
        printf '        proxy_set_header Host $host;\n'
        echo "        # 传递客户端真实 IP"
        printf '        proxy_set_header X-Real-IP $remote_addr;\n'
        echo "        # 传递完整代理链路 IP"
        printf '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n'
        echo "        # 传递原始访问协议"
        printf '        proxy_set_header X-Forwarded-Proto $scheme;\n'
        echo "        # 支持 WebSocket 升级"
        printf '        proxy_set_header Upgrade $http_upgrade;\n'
        echo "        # 保持 WebSocket 连接升级标记"
        echo '        proxy_set_header Connection "upgrade";'
        echo
        echo "        # 后端读取超时时间"
        echo "        proxy_read_timeout 120s;"
        echo "        # 后端发送超时时间"
        echo "        proxy_send_timeout 120s;"
        echo "        # 后端连接超时时间"
        echo "        proxy_connect_timeout 60s;"
        echo "        # 开启代理缓冲"
        echo "        proxy_buffering on;"
        echo "    }"
        echo "}"
        echo
        echo "# HTTP 80 端口跳转到 HTTPS 443；不需要时可删除整个 server 块"
        echo "server {"
        echo "    # 监听普通 HTTP 80 端口"
        echo "    listen 80;"
        echo "    # 使用与 HTTPS 服务相同的域名"
        echo "    server_name your-domain.com;"
        echo "    # 永久重定向到 HTTPS，并保留原始路径和查询参数"
        printf '    return 301 https://$host$request_uri;\n'
        echo "}"
    } > "$output_file"
}

write_nginx_conf_from_tmp() {
    local id="$1" nginx_dir="$2" tmp_file="$3" conf_dir out_file public_url answer
    conf_dir="$nginx_dir/conf.d"
    mkdir -p "$conf_dir" || return 1
    out_file="$conf_dir/$id.conf"
    cp "$tmp_file" "$out_file" || return 1
    green "配置已写入: $out_file"

    ensure_nginx_include "$nginx_dir" || return 1
    reload_nginx || return 1

    public_url="$(public_url_from_conf "$out_file" 2>/dev/null || true)"
    if [ -n "$public_url" ]; then
        record_nginx_project_meta "$id" "$public_url"
        green "公网地址已记录: $public_url"
    else
        muted "未能从配置中读取 server_name，跳过 PUBLIC_URL 回写。"
    fi

    readp "  Nginx 重载成功，是否备份到 $(project_config_dir "$id") ? [y/N] → " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        sync_nginx_conf_to_project "$id" "$out_file" || return 1
    else
        yellow "已跳过同步备份。"
    fi
}

manual_edit_nginx_conf() {
    local id="$1" nginx_dir="$2" seed_file="$3" tmp_file out_file
    tmp_file="$(mktemp)"
    if [ -n "$seed_file" ] && [ -f "$seed_file" ]; then
        cp "$seed_file" "$tmp_file" || return 1
    else
        create_manual_nginx_conf_seed "$id" "$tmp_file"
    fi
    out_file="$(nginx_project_conf "$nginx_dir" "$id")"
    edit_conf_with_vim "$tmp_file" || {
        rm -f "$tmp_file"
        return 1
    }
    confirm_tmp_conf_write "$tmp_file" "$out_file" || {
        rm -f "$tmp_file"
        return 0
    }
    write_nginx_conf_from_tmp "$id" "$nginx_dir" "$tmp_file"
    local result=$?
    rm -f "$tmp_file"
    return "$result"
}

record_nginx_project_meta() {
    local id="$1" public_url="$2" app_path
    if [ "$#" -ge 3 ]; then
        public_url="$3"
    fi
    app_path="$(app_project_path "$id")"
    if project_files_exist "$id" || [ -d "$app_path" ]; then
        set_project_conf_value "$id" "PUBLIC_URL" "$public_url"
    else
        muted "项目未安装到 $app_path，跳过 project.conf 回写。"
    fi
}

clear_nginx_project_meta() {
    local id="$1" app_path
    app_path="$(app_project_path "$id")"
    if project_files_exist "$id" || [ -d "$app_path" ]; then
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
    local id="${1:-}" nginx_dir current_conf defaults_conf project_conf template_file tmp_file target_file default_port
    local old_domain old_listen old_host old_port old_cert old_key old_body
    local action domain upstream_host upstream_port listen_port ssl_cert ssl_key body_size result

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
        qiqi_menu_item "3" "手动编辑配置（vim）"
        qiqi_menu_item "0" "返回"
        readp "  请输入选项 → " action
        case "$action" in
            1) ;;
            2) delete_project_reverse_proxy "$id"; return $? ;;
            3) manual_edit_nginx_conf "$id" "$nginx_dir" "$current_conf"; return $? ;;
            0) return 0 ;;
            *) red "无效选项。"; return 1 ;;
        esac
    fi

    load_project_meta "$id"
    project_conf="$(project_nginx_conf_file "$id")"
    if [ -n "$project_conf" ]; then
        template_file="$project_conf"
        if [ ! -f "$current_conf" ]; then
            qiqi_section "创建反代配置"
            muted "检测到项目内置 Nginx 配置: $template_file"
            qiqi_menu_item "1" "使用项目内置配置生成"
            qiqi_menu_item "99" "手动编辑配置（vim）"
            qiqi_menu_item "0" "返回"
            readp "  请输入选项 → " action
            case "$action" in
                1|"") ;;
                99) manual_edit_nginx_conf "$id" "$nginx_dir" "$template_file"; return $? ;;
                0) return 0 ;;
                *) red "无效选项。"; return 1 ;;
            esac
        else
            muted "检测到项目内置 Nginx 配置，优先使用: $template_file"
        fi
    else
        select_template "${NGINX_TEMPLATE:-default}" || return 1
        if [ "$SELECTED_TEMPLATE" = "__manual__" ]; then
            manual_edit_nginx_conf "$id" "$nginx_dir" ""
            return $?
        fi
        template_file="$TEMPLATE_DIR/$SELECTED_TEMPLATE.conf"
        [ -f "$template_file" ] || {
            red "模板不存在: $template_file"
            return 1
        }
    fi

    if [ -f "$current_conf" ]; then
        defaults_conf="$current_conf"
    else
        defaults_conf="$template_file"
    fi
    old_domain="$(extract_current_value "$defaults_conf" domain)"
    old_listen="$(extract_current_value "$defaults_conf" listen)"
    old_host="$(extract_current_value "$defaults_conf" upstream_host)"
    old_port="$(extract_current_value "$defaults_conf" upstream_port)"
    old_cert="$(extract_current_value "$defaults_conf" cert)"
    old_key="$(extract_current_value "$defaults_conf" key)"
    old_body="$(extract_current_value "$defaults_conf" body)"
    default_port="${ACCESS_PORT:-$(infer_compose_port "$(project_runtime_path "$id")/docker-compose.yml")}"

    qiqi_section "填写反代参数"
    muted "直接回车会使用括号内默认值。"
    readp "  绑定域名 [${old_domain:-your-domain.com}] → " domain
    domain="${domain:-${old_domain:-your-domain.com}}"
    if [ -z "$project_conf" ]; then
        readp "  上游主机 [${old_host:-${ACCESS_HOST:-127.0.0.1}}] → " upstream_host
        upstream_host="${upstream_host:-${old_host:-${ACCESS_HOST:-127.0.0.1}}}"
        readp "  上游端口 [${old_port:-${default_port:-3000}}] → " upstream_port
        upstream_port="${upstream_port:-${old_port:-${default_port:-3000}}}"
    fi
    readp "  HTTPS 监听端口 [${old_listen:-443}] → " listen_port
    listen_port="${listen_port:-${old_listen:-443}}"
    case "$listen_port" in
        ''|*[!0-9]*) red "HTTPS 监听端口必须是数字。"; return 1 ;;
    esac
    choose_http_redirect "$listen_port" "$defaults_conf"
    readp "  SSL 证书路径 [${old_cert:-/path/to/fullchain.pem}] → " ssl_cert
    ssl_cert="${ssl_cert:-${old_cert:-/path/to/fullchain.pem}}"
    readp "  SSL 私钥路径 [${old_key:-/path/to/privkey.pem}] → " ssl_key
    ssl_key="${ssl_key:-${old_key:-/path/to/privkey.pem}}"
    body_size="${old_body:-50m}"

    tmp_file="$(mktemp)"
    if [ -n "$project_conf" ]; then
        render_project_nginx_conf "$template_file" "$tmp_file" "$domain" "$listen_port" "$ssl_cert" "$ssl_key" "$body_size" "$HTTP_REDIRECT_ENABLED" || {
            rm -f "$tmp_file"
            return 1
        }
    else
        render_template "$template_file" "$tmp_file" "$domain" "$listen_port" "$upstream_host" "$upstream_port" "$ssl_cert" "$ssl_key" "$body_size" "$HTTP_REDIRECT_ENABLED" || {
            rm -f "$tmp_file"
            return 1
        }
    fi

    target_file="$(nginx_project_conf "$nginx_dir" "$id")"
    confirm_tmp_conf_write "$tmp_file" "$target_file" || {
        rm -f "$tmp_file"
        return 0
    }
    write_nginx_conf_from_tmp "$id" "$nginx_dir" "$tmp_file"
    result=$?
    rm -f "$tmp_file"
    return "$result"
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
    printf "  ${QIQI_GREEN}[ 0 ]${QIQI_PLAIN} ${QIQI_WHITE}返回${QIQI_PLAIN}\n"
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
        printf "  ${QIQI_GREEN}-${QIQI_PLAIN} %s\n" "$file"
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
        qiqi_menu_item "0" "返回主菜单"
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
