#!/usr/bin/env bash
export LANG=en_US.UTF-8

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "$COMMON_DIR/.." && pwd)"

if [ -f "$COMMON_DIR/theme.sh" ]; then
    # shellcheck source=theme.sh
    . "$COMMON_DIR/theme.sh"
else
    # theme.sh 是可选增强。缺失时使用高对比 fallback，确保脚本仍可运行。
    QIQI_GITHUB_URL="${QIQI_GITHUB_URL:-https://github.com/qiqi-style}"
    QIQI_YOUTUBE_URL="${QIQI_YOUTUBE_URL:-https://www.youtube.com/@qiqi-style}"
    QIQI_BLOG_URL="${QIQI_BLOG_URL:-https://qiaiai.xyz}"
    QIQI_PINK='\033[38;5;161m'
    QIQI_GREEN='\033[38;5;34m'
    QIQI_ORANGE='\033[38;5;166m'
    QIQI_CYAN='\033[38;5;31m'
    QIQI_BLUE='\033[38;5;31m'
    QIQI_GRAY='\033[38;5;244m'
    QIQI_WHITE=''
    QIQI_RED='\033[38;5;160m'
    QIQI_PLAIN='\033[0m'
    pink(){ printf "${QIQI_PINK}%s${QIQI_PLAIN}\n" "$1"; }
    green(){ printf "${QIQI_GREEN}%s${QIQI_PLAIN}\n" "$1"; }
    yellow(){ printf "${QIQI_ORANGE}%s${QIQI_PLAIN}\n" "$1"; }
    red(){ printf "${QIQI_RED}%s${QIQI_PLAIN}\n" "$1"; }
    cyan(){ printf "${QIQI_CYAN}%s${QIQI_PLAIN}\n" "$1"; }
    blue(){ printf "${QIQI_BLUE}%s${QIQI_PLAIN}\n" "$1"; }
    muted(){ printf "${QIQI_GRAY}%s${QIQI_PLAIN}\n" "$1"; }
    readp(){ local prompt="$1" __var="$2"; IFS='' read -r -p "$prompt" "$__var"; }
    pause(){ local _x; readp "按回车键继续..." _x; }
    qiqi_section(){ printf "\n${QIQI_PINK}───────────────────── %s ─────────────────────${QIQI_PLAIN}\n" "$1"; }
    qiqi_menu_item(){ printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN}  %s\n" "$1" "$2"; }
    qiqi_banner(){
        printf "\n${QIQI_CYAN}%s${QIQI_PLAIN} %s\n%s\n" "$1" "$2" "$3"
        printf "  ${QIQI_GREEN}⬥ qiqi Github   :${QIQI_PLAIN}  %s\n" "$QIQI_GITHUB_URL"
        printf "  ${QIQI_GREEN}⬥ qiqi YouTube  :${QIQI_PLAIN}  %s\n" "$QIQI_YOUTUBE_URL"
        printf "  ${QIQI_GREEN}⬥ qiqi 博客     :${QIQI_PLAIN}  %s\n" "$QIQI_BLOG_URL"
        printf "  项目地址：${QIQI_CYAN}%s${QIQI_PLAIN}\n" "${4:-https://github.com/qiqi-style/DN_Tools}"
    }
fi

PROJECT_TITLE="${PROJECT_TITLE:-DN_Tools}"
PROJECT_VERSION="${PROJECT_VERSION:-v1.0.0}"
PROJECT_DESCRIPTION="${PROJECT_DESCRIPTION:-Docker 项目部署、管理与 Nginx 反代工具}"
PROJECT_URL="${PROJECT_URL:-https://github.com/qiqi-style/DN_Tools}"

TARGET_BASE_DIR="${TARGET_BASE_DIR:-/app}"
BACKUP_DIR="${BACKUP_DIR:-$TARGET_BASE_DIR/backup}"
DOCKER_SOURCE_DIR="${DOCKER_SOURCE_DIR:-$TOOL_ROOT/docker}"
NGINX_CONFIG_SOURCE_DIR="${NGINX_CONFIG_SOURCE_DIR:-$TOOL_ROOT/nginx-config}"

PROJECT_NAME=""
DESCRIPTION=""
PROJECT_META_URL=""
ACCESS_SCHEME=""
ACCESS_HOST=""
ACCESS_PORT=""
ACCESS_PATH=""
HEALTH_URL=""
NGINX_TEMPLATE=""
PUBLIC_URL=""

require_root() {
    if [ "${DN_TOOLS_ALLOW_NON_ROOT:-0}" = "1" ]; then
        return 0
    fi
    if [ "$EUID" -ne 0 ]; then
        red "错误: 请使用 sudo/root 运行 DN_Tools。"
        exit 1
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

docker_available() {
    command_exists docker
}

nginx_available() {
    command_exists nginx
}

install_docker_placeholder() {
    yellow "Docker 自动安装功能当前是占位提示。"
    muted "请先按服务器系统安装 Docker 与 Docker Compose，之后重新进入 DN_Tools。"
}

install_nginx_placeholder() {
    yellow "Nginx 自动安装功能当前是占位提示。"
    muted "请先按服务器系统安装 Nginx，之后重新进入 DN_Tools。"
}

show_environment_status() {
    qiqi_section "运行环境检测"
    if docker_available; then
        green "  Docker : 已检测到"
    else
        red "  Docker : 未检测到"
    fi

    if nginx_available; then
        green "  Nginx  : 已检测到"
    elif [ -n "${NGINX_DIR_OVERRIDE:-}" ]; then
        yellow "  Nginx  : 未检测到命令，使用 NGINX_DIR_OVERRIDE=$NGINX_DIR_OVERRIDE"
    else
        red "  Nginx  : 未检测到"
    fi

    if [ -d "$TARGET_BASE_DIR" ]; then
        green "  应用目录: $TARGET_BASE_DIR"
    else
        yellow "  应用目录: $TARGET_BASE_DIR 尚不存在，安装项目时会创建。"
    fi
}

trim() {
    printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

strip_quotes() {
    local value="$1"
    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    printf '%s' "$value"
}

reset_project_meta() {
    local id="$1"
    PROJECT_NAME="$id"
    DESCRIPTION="自定义 Docker 项目"
    PROJECT_META_URL=""
    ACCESS_SCHEME="http"
    ACCESS_HOST="127.0.0.1"
    ACCESS_PORT=""
    ACCESS_PATH="/"
    HEALTH_URL=""
    NGINX_TEMPLATE="default"
    PUBLIC_URL=""
}

read_project_conf() {
    local conf_file="$1"
    local line key value
    [ -f "$conf_file" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        line="$(trim "$line")"
        [ -z "$line" ] && continue
        case "$line" in \#*) continue ;; esac
        case "$line" in *=*) ;; *) continue ;; esac
        key="$(trim "${line%%=*}")"
        value="$(trim "${line#*=}")"
        value="$(strip_quotes "$value")"
        case "$key" in
            PROJECT_NAME) PROJECT_NAME="$value" ;;
            DESCRIPTION) DESCRIPTION="$value" ;;
            PROJECT_URL) PROJECT_META_URL="$value" ;;
            ACCESS_SCHEME) ACCESS_SCHEME="$value" ;;
            ACCESS_HOST) ACCESS_HOST="$value" ;;
            ACCESS_PORT) ACCESS_PORT="$value" ;;
            ACCESS_PATH) ACCESS_PATH="$value" ;;
            HEALTH_URL) HEALTH_URL="$value" ;;
            NGINX_TEMPLATE) NGINX_TEMPLATE="$value" ;;
            PUBLIC_URL) PUBLIC_URL="$value" ;;
        esac
    done < "$conf_file"
}

source_project_path() {
    printf '%s/%s' "$DOCKER_SOURCE_DIR" "$1"
}

app_project_path() {
    printf '%s/%s' "$TARGET_BASE_DIR" "$1"
}

project_has_template() {
    [ -f "$(source_project_path "$1")/docker-compose.yml" ]
}

project_is_installed() {
    [ -f "$(app_project_path "$1")/docker-compose.yml" ]
}

project_runtime_path() {
    if project_is_installed "$1"; then
        app_project_path "$1"
    else
        source_project_path "$1"
    fi
}

project_conf_file() {
    local id="$1"
    if [ -f "$(app_project_path "$id")/project.conf" ]; then
        printf '%s/project.conf' "$(app_project_path "$id")"
    elif [ -f "$(source_project_path "$id")/project.conf" ]; then
        printf '%s/project.conf' "$(source_project_path "$id")"
    fi
}

project_conf_file_for_write() {
    local id="$1" path
    path="$(app_project_path "$id")"
    mkdir -p "$path"
    printf '%s/project.conf' "$path"
}

load_project_meta() {
    local id="$1" conf_file
    reset_project_meta "$id"
    conf_file="$(project_conf_file "$id")"
    [ -n "$conf_file" ] && read_project_conf "$conf_file"
}

quote_conf_value() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

set_project_conf_value() {
    local id="$1" key="$2" value="$3" conf_file tmp quoted
    conf_file="$(project_conf_file_for_write "$id")"
    if [ ! -f "$conf_file" ]; then
        write_project_conf_defaults "$id" "$conf_file"
    fi
    quoted="$(quote_conf_value "$value")"
    tmp="$(mktemp)"
    awk -v key="$key" -v value="$quoted" '
        BEGIN { done=0; line=key "=\"" value "\"" }
        $0 ~ "^" key "=" { print line; done=1; next }
        { print }
        END { if (!done) print line }
    ' "$conf_file" > "$tmp"
    cp "$tmp" "$conf_file"
    rm -f "$tmp"
}

write_project_conf_defaults() {
    local id="$1" conf_file="$2" port health
    port="$(infer_compose_port "$(project_runtime_path "$id")/docker-compose.yml")"
    health=""
    [ -n "$port" ] && health="http://127.0.0.1:$port/"
    cat > "$conf_file" << EOF
PROJECT_NAME="$id"
DESCRIPTION="自定义 Docker 项目"
PROJECT_URL=""
ACCESS_SCHEME="http"
ACCESS_HOST="127.0.0.1"
ACCESS_PORT="$port"
ACCESS_PATH="/"
HEALTH_URL="$health"
NGINX_TEMPLATE="default"
PUBLIC_URL=""
EOF
}

list_source_project_ids() {
    local d id
    [ -d "$DOCKER_SOURCE_DIR" ] || return 0
    for d in "$DOCKER_SOURCE_DIR"/*; do
        [ -d "$d" ] || continue
        [ -f "$d/docker-compose.yml" ] || continue
        id="$(basename "$d")"
        printf '%s\n' "$id"
    done | sort
}

list_app_project_ids() {
    local d id
    [ -d "$TARGET_BASE_DIR" ] || return 0
    for d in "$TARGET_BASE_DIR"/*; do
        [ -d "$d" ] || continue
        [ -f "$d/docker-compose.yml" ] || continue
        id="$(basename "$d")"
        case "$id" in backup|backups) continue ;; esac
        printf '%s\n' "$id"
    done | sort
}

list_custom_app_project_ids() {
    local id
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        project_has_template "$id" || printf '%s\n' "$id"
    done < <(list_app_project_ids)
}

list_project_ids() {
    local seen="|" id
    # /app 优先。若 /app 和 /opt/DN_Tools/docker 中同名，所有管理都以 /app 为准。
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        case "$seen" in *"|$id|"*) ;; *) printf '%s\n' "$id"; seen="${seen}${id}|" ;; esac
    done < <(list_app_project_ids)

    while IFS= read -r id; do
        [ -n "$id" ] || continue
        case "$seen" in *"|$id|"*) ;; *) printf '%s\n' "$id"; seen="${seen}${id}|" ;; esac
    done < <(list_source_project_ids)
}

collect_installed_ids() {
    local id
    while IFS= read -r id; do
        [ -n "$id" ] && project_is_installed "$id" && printf '%s\n' "$id"
    done < <(list_project_ids)
}

copy_builtin_project_to_app() {
    local id="$1" mode="${2:-keep}" source_path target_path
    source_path="$(source_project_path "$id")"
    target_path="$(app_project_path "$id")"

    if [ ! -f "$source_path/docker-compose.yml" ]; then
        red "未找到内置项目: $source_path/docker-compose.yml"
        return 1
    fi

    if [ -e "$target_path" ]; then
        if [ "$mode" != "replace" ]; then
            if [ -f "$target_path/docker-compose.yml" ]; then
                muted ">>> $target_path 已存在，保留现有项目。"
                return 0
            fi
            yellow ">>> $target_path 已存在但不是 Docker Compose 项目，已跳过。"
            return 1
        fi
        rm -rf "$target_path"
    fi

    mkdir -p "$TARGET_BASE_DIR" || return 1
    mkdir -p "$target_path" || return 1
    pink ">>> 正在复制内置项目到 $target_path"
    cp -a "$source_path/." "$target_path/" || return 1
    [ -f "$target_path/project.conf" ] || write_project_conf_defaults "$id" "$target_path/project.conf"
}

reinstall_builtin_project() {
    local id="$1" target_path
    target_path="$(app_project_path "$id")"

    project_has_template "$id" || {
        red "未找到内置模板: $(source_project_path "$id")/docker-compose.yml"
        return 1
    }

    if [ -d "$target_path" ]; then
        red "重新安装会覆盖项目目录: $target_path"
        confirm_action "  确认重新安装 $id" || return 1
        backup_project_dir "$id" || return 1
    fi

    copy_builtin_project_to_app "$id" replace
}

compose_cmd_available() {
    docker compose version >/dev/null 2>&1 || command_exists docker-compose
}

compose_run() {
    local workdir="$1"
    shift
    if docker compose version >/dev/null 2>&1; then
        (cd "$workdir" && docker compose "$@")
    elif command_exists docker-compose; then
        (cd "$workdir" && docker-compose "$@")
    else
        red "错误: 未检测到 docker compose 或 docker-compose。"
        return 127
    fi
}

infer_compose_port() {
    local compose_file="$1"
    [ -f "$compose_file" ] || return 0
    awk '
        /ports:[[:space:]]*$/ { in_ports=1; next }
        in_ports && /^[^[:space:]#]/ { in_ports=0 }
        in_ports && /:[0-9]+/ {
            line=$0
            sub(/#.*/, "", line)
            gsub(/["[:space:]]/, "", line)
            sub(/^-/, "", line)
            n=split(line, a, ":")
            if (n >= 2) {
                candidate=a[n-1]
                gsub(/[^0-9]/, "", candidate)
                if (candidate != "") {
                    print candidate
                    exit
                }
            }
        }
    ' "$compose_file"
}

project_local_url() {
    local id="$1" port clean_path
    load_project_meta "$id"
    port="$ACCESS_PORT"
    [ -n "$port" ] || port="$(infer_compose_port "$(project_runtime_path "$id")/docker-compose.yml")"
    if [ -z "$port" ]; then
        printf '未识别'
        return 0
    fi
    clean_path="${ACCESS_PATH:-/}"
    case "$clean_path" in /*) ;; *) clean_path="/$clean_path" ;; esac
    printf '%s://%s:%s%s' "${ACCESS_SCHEME:-http}" "${ACCESS_HOST:-127.0.0.1}" "$port" "$clean_path"
}

check_url() {
    local url="$1"
    if ! command_exists curl; then
        printf "${QIQI_GRAY}[未检测]${QIQI_PLAIN}"
        return 0
    fi
    if [ -z "$url" ] || [ "$url" = "未识别" ] || [ "$url" = "未配置" ]; then
        printf "${QIQI_GRAY}[未配置]${QIQI_PLAIN}"
        return 0
    fi
    if curl -fsS --connect-timeout 3 --max-time 5 "$url" >/dev/null 2>&1; then
        printf "${QIQI_GREEN}[连通]${QIQI_PLAIN}"
    else
        printf "${QIQI_RED}[不可达]${QIQI_PLAIN}"
    fi
}

project_container_names() {
    local compose_file="$1"
    [ -f "$compose_file" ] || return 0
    awk '
        /^[[:space:]]*container_name:[[:space:]]*/ {
            sub(/^[^:]*:[[:space:]]*/, "")
            gsub(/[" ]/, "")
            print
        }
    ' "$compose_file" | awk 'BEGIN { first=1 } { if (!first) printf ", "; printf "%s", $0; first=0 } END { if (!first) printf "\n" }'
}

project_images() {
    local compose_file="$1"
    [ -f "$compose_file" ] || return 0
    awk '
        /^[[:space:]]*image:[[:space:]]*/ {
            sub(/^[^:]*:[[:space:]]*/, "")
            gsub(/[" ]/, "")
            print
        }
    ' "$compose_file" | awk 'BEGIN { first=1 } { if (!first) printf ", "; printf "%s", $0; first=0 } END { if (!first) printf "\n" }'
}

project_running_status() {
    local id="$1" path ids running
    if ! project_is_installed "$id"; then
        printf "${QIQI_GRAY}未安装${QIQI_PLAIN}"
        return 0
    fi
    if ! docker_available || ! compose_cmd_available; then
        printf "${QIQI_GRAY}未检测${QIQI_PLAIN}"
        return 0
    fi
    path="$(app_project_path "$id")"
    ids="$(compose_run "$path" ps -q 2>/dev/null || true)"
    running="$(compose_run "$path" ps --status running -q 2>/dev/null || true)"
    if [ -z "$ids" ]; then
        printf "${QIQI_RED}已停止${QIQI_PLAIN}"
    elif [ -n "$running" ]; then
        printf "${QIQI_GREEN}运行中${QIQI_PLAIN}"
    else
        printf "${QIQI_ORANGE}未完全运行${QIQI_PLAIN}"
    fi
}

placeholder_files() {
    local path="$1"
    [ -d "$path" ] || return 0
    find "$path" -maxdepth 2 -type f \
        ! -name '*.example' \
        ! -name 'docker-compose.yml' \
        ! -name 'compose.yml' \
        ! -name 'compose.yaml' \
        ! -path '*/data/*' \
        ! -path '*/logs/*' \
        ! -path '*/auth-dir/*' \
        -exec grep -Il 'DN_TOOLS_CHANGE_ME' {} + 2>/dev/null
}

confirm_no_placeholder_or_continue() {
    local path="$1" files answer
    files="$(placeholder_files "$path")"
    [ -z "$files" ] && return 0

    red "检测到尚未替换的安全占位值，默认不启动项目:"
    printf '%s\n' "$files" | sed 's/^/  - /'
    muted "请编辑上述文件，把 DN_TOOLS_CHANGE_ME_* 改成自己的强密码或密钥。"
    readp "  仍要继续执行? [y/N] → " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

detect_nginx_dir() {
    local conf_path p
    if [ -n "${NGINX_DIR_OVERRIDE:-}" ]; then
        printf '%s' "$NGINX_DIR_OVERRIDE"
        return 0
    fi

    if nginx_available; then
        conf_path="$(nginx -t 2>&1 | awk -F 'configuration file ' '/configuration file / {print $2; exit}' | awk '{print $1}')"
        if [ -z "$conf_path" ] || [ ! -f "$conf_path" ]; then
            conf_path="$(nginx -V 2>&1 | grep -o -E '\-\-conf-path=[^ ]+' | cut -d '=' -f 2)"
        fi
        if [ -n "$conf_path" ] && [ -f "$conf_path" ]; then
            dirname "$conf_path"
            return 0
        fi
    fi

    for p in "/etc/nginx" "/usr/local/nginx/conf" "/opt/homebrew/etc/nginx"; do
        if [ -d "$p" ]; then
            printf '%s' "$p"
            return 0
        fi
    done
}

nginx_project_conf() {
    local nginx_dir="$1" id="$2"
    printf '%s/conf.d/%s.conf' "$nginx_dir" "$id"
}

project_public_url() {
    local id="$1" nginx_dir conf domain listen_port suffix
    load_project_meta "$id"
    if [ -n "$PUBLIC_URL" ]; then
        printf '%s' "$PUBLIC_URL"
        return 0
    fi

    nginx_dir="$(detect_nginx_dir)"
    [ -n "$nginx_dir" ] || {
        printf '未配置'
        return 0
    }
    conf="$(nginx_project_conf "$nginx_dir" "$id")"
    [ -f "$conf" ] || {
        printf '未配置'
        return 0
    }
    domain="$(awk '/server_name/ {gsub(";", "", $2); print $2; exit}' "$conf")"
    listen_port="$(awk '/listen[[:space:]]+[0-9]+/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+/) {gsub(";", "", $i); print $i; exit}}' "$conf")"
    [ -n "$domain" ] || {
        printf '未配置'
        return 0
    }
    suffix=""
    if [ -n "$listen_port" ] && [ "$listen_port" != "443" ] && [ "$listen_port" != "80" ]; then
        suffix=":$listen_port"
    fi
    printf 'https://%s%s' "$domain" "$suffix"
}

ensure_nginx_include() {
    local nginx_dir="$1" conf_file tmp
    conf_file="$nginx_dir/nginx.conf"
    [ -f "$conf_file" ] || {
        red "错误: 未找到 Nginx 主配置 $conf_file"
        return 1
    }
    if grep -Eq 'conf\.d/\*\.conf|conf\.d/\*.conf' "$conf_file"; then
        green "Nginx 主配置已包含 conf.d/*.conf。"
        return 0
    fi

    tmp="$(mktemp)"
    awk '
        BEGIN { inserted=0 }
        {
            print
            if (!inserted && $0 ~ /^[[:space:]]*http[[:space:]]*\{/) {
                print "    include ./conf.d/*.conf;"
                inserted=1
            }
        }
        END { if (!inserted) exit 2 }
    ' "$conf_file" > "$tmp"
    if [ $? -ne 0 ]; then
        rm -f "$tmp"
        red "错误: 未找到 http { 块，无法自动加入 conf.d 引入。"
        return 1
    fi
    cp "$tmp" "$conf_file"
    rm -f "$tmp"
    green "已向 nginx.conf 加入 include ./conf.d/*.conf;"
}

reload_nginx() {
    if [ "${SKIP_NGINX_RELOAD:-0}" = "1" ]; then
        yellow "已跳过 nginx -t/reload（SKIP_NGINX_RELOAD=1）。"
        return 0
    fi
    if ! nginx_available; then
        red "错误: 未检测到 nginx 命令，无法测试或重载。"
        return 1
    fi
    pink ">>> 正在测试 Nginx 配置..."
    nginx -t || {
        red "Nginx 配置测试失败，已取消 reload。"
        return 1
    }
    pink ">>> 正在重载 Nginx..."
    nginx -s reload
}

backup_project_dir() {
    local id="$1" path timestamp backup_file count file
    path="$(app_project_path "$id")"
    [ -d "$path" ] || {
        red "错误: 项目未安装到 $path，无法备份。"
        return 1
    }
    mkdir -p "$BACKUP_DIR"
    timestamp="$(date +"%Y%m%d-%H%M%S")"
    backup_file="$BACKUP_DIR/${id}-${timestamp}.tar.gz"
    pink ">>> 正在备份 $id 到 $backup_file"
    tar -zcf "$backup_file" -C "$(dirname "$path")" "$(basename "$path")" || return 1

    count=0
    for file in $(ls -t "$BACKUP_DIR"/"$id"-*.tar.gz 2>/dev/null); do
        count=$((count + 1))
        if [ "$count" -gt 3 ]; then
            rm -f "$file"
        fi
    done
    green "备份完成: $backup_file"
}

confirm_action() {
    local prompt="$1" answer
    readp "$prompt [y/N] → " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}
