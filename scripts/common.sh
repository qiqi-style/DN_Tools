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
PROJECT_VERSION="${PROJECT_VERSION:-v1.2.0}"
PROJECT_DESCRIPTION="${PROJECT_DESCRIPTION:-Docker 项目部署、管理与 Nginx 反代工具}"
PROJECT_URL="${PROJECT_URL:-https://github.com/qiqi-style/DN_Tools}"

TARGET_BASE_DIR="${TARGET_BASE_DIR:-/app}"
BACKUP_DIR="${BACKUP_DIR:-$TARGET_BASE_DIR/backup}"
DOCKER_SOURCE_DIR="${DOCKER_SOURCE_DIR:-$TOOL_ROOT/docker}"
NGINX_CONFIG_SOURCE_DIR="${NGINX_CONFIG_SOURCE_DIR:-$TOOL_ROOT/nginx-config}"
DNT_CONFIG_DIR_NAME="${DNT_CONFIG_DIR_NAME:-dntool-config}"
DNT_STATE_DIR_NAME="${DNT_STATE_DIR_NAME:-.dntool}"

PROJECT_NAME=""
DESCRIPTION=""
PROJECT_META_URL=""
IMAGE_VERSION=""
ACCESS_SCHEME=""
ACCESS_HOST=""
ACCESS_PORT=""
ACCESS_PATH=""
HEALTH_URL=""
NGINX_TEMPLATE=""
PUBLIC_URL=""

# 这些检测在项目列表中会被重复调用。缓存命令类型和 Nginx 目录，避免每个项目都
# 额外执行一次 `docker compose version` / `nginx -t`。
DN_TOOLS_COMPOSE_KIND="${DN_TOOLS_COMPOSE_KIND:-}"
DN_TOOLS_NGINX_DIR_DETECTED="${DN_TOOLS_NGINX_DIR_DETECTED:-0}"
DN_TOOLS_NGINX_DIR_CACHE="${DN_TOOLS_NGINX_DIR_CACHE:-}"
DN_TOOLS_LINUX_DISTRIBUTION="${DN_TOOLS_LINUX_DISTRIBUTION:-}"

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

detect_linux_distribution() {
    if [ ! -r /etc/os-release ]; then
        red "无法识别系统：未找到 /etc/os-release。"
        return 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        ubuntu|debian|centos) DN_TOOLS_LINUX_DISTRIBUTION="$ID" ;;
        *)
            red "暂不支持的系统：${PRETTY_NAME:-${ID:-未知系统}}。"
            muted "当前支持 Ubuntu、Debian 和 CentOS。"
            return 1
            ;;
    esac
}

start_and_enable_service() {
    local service_name="$1"
    if ! command_exists systemctl; then
        yellow "未检测到 systemctl，请手动启动服务：$service_name"
        return 0
    fi

    if systemctl enable --now "$service_name"; then
        green "服务已启动并设为开机自启：$service_name"
    else
        red "服务启动失败：$service_name"
        muted "请检查：systemctl status $service_name"
        return 1
    fi
}

add_docker_apt_repository() {
    local distribution architecture codename
    distribution="$1"

    apt-get update || return 1
    apt-get install -y ca-certificates curl || return 1
    install -m 0755 -d /etc/apt/keyrings || return 1
    curl -fsSL "https://download.docker.com/linux/$distribution/gpg" -o /etc/apt/keyrings/docker.asc || return 1
    chmod a+r /etc/apt/keyrings/docker.asc || return 1

    architecture="$(dpkg --print-architecture)" || return 1
    codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    if [ -z "$codename" ]; then
        red "无法识别系统代号，无法配置 Docker 官方软件源。"
        return 1
    fi
    printf '%s\n' \
        "deb [arch=$architecture signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$distribution $codename stable" \
        > /etc/apt/sources.list.d/docker.list || return 1
    apt-get update
}

install_docker() {
    local distribution package_manager
    if docker_available; then
        green "Docker 已安装，无需重复安装。"
        compose_cmd_available || yellow "提示：未检测到 Docker Compose，请按系统提示补装。"
        return 0
    fi

    detect_linux_distribution || return 1
    distribution="$DN_TOOLS_LINUX_DISTRIBUTION"
    qiqi_section "安装 Docker"
    pink ">>> 正在为 $distribution 安装 Docker 与 Docker Compose..."

    case "$distribution" in
        ubuntu|debian)
            add_docker_apt_repository "$distribution" || return 1
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos)
            if command_exists dnf; then
                package_manager="dnf"
                "$package_manager" install -y dnf-plugins-core || return 1
            elif command_exists yum; then
                package_manager="yum"
                "$package_manager" install -y yum-utils || return 1
            else
                red "未找到 dnf 或 yum，无法安装 Docker。"
                return 1
            fi
            "$package_manager" config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || return 1
            "$package_manager" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
    esac || {
        red "Docker 安装失败。"
        return 1
    }

    start_and_enable_service docker || return 1
    if ! docker_available; then
        red "Docker 命令仍不可用，请检查安装日志。"
        return 1
    fi
    if compose_cmd_available; then
        green "Docker 与 Docker Compose 安装完成。"
    else
        yellow "Docker 已安装，但未检测到 Docker Compose。"
        muted "请根据系统软件源安装 Docker Compose 后重试。"
    fi
}

ensure_nginx_app_conf_link() {
    local app_nginx_dir conf_link
    app_nginx_dir="$TARGET_BASE_DIR/nginx"
    conf_link="$app_nginx_dir/conf"

    [ -d /etc/nginx ] || {
        yellow "未找到 /etc/nginx，跳过创建 Nginx 配置入口。"
        return 0
    }
    mkdir -p "$app_nginx_dir" || {
        red "无法创建 Nginx 目录: $app_nginx_dir"
        return 1
    }

    if [ -L "$conf_link" ]; then
        if [ "$(readlink "$conf_link")" = "/etc/nginx" ]; then
            green "Nginx 配置入口已存在: $conf_link -> /etc/nginx"
            return 0
        fi
        yellow "配置入口已存在且指向其他位置，保留不变: $conf_link -> $(readlink "$conf_link")"
        return 0
    fi
    if [ -e "$conf_link" ]; then
        yellow "配置入口路径已存在，保留不变: $conf_link"
        return 0
    fi

    ln -s /etc/nginx "$conf_link" || {
        red "创建 Nginx 配置入口失败: $conf_link"
        return 1
    }
    green "已创建 Nginx 配置入口: $conf_link -> /etc/nginx"
}

install_nginx() {
    local distribution package_manager
    if nginx_available; then
        green "Nginx 已安装，无需重复安装。"
        ensure_nginx_app_conf_link
        return $?
    fi

    detect_linux_distribution || return 1
    distribution="$DN_TOOLS_LINUX_DISTRIBUTION"
    qiqi_section "安装 Nginx"
    pink ">>> 正在为 $distribution 安装 Nginx..."

    case "$distribution" in
        ubuntu|debian)
            apt-get update && apt-get install -y nginx
            ;;
        centos)
            if command_exists dnf; then
                package_manager="dnf"
            elif command_exists yum; then
                package_manager="yum"
            else
                red "未找到 dnf 或 yum，无法安装 Nginx。"
                return 1
            fi
            "$package_manager" install -y nginx
            ;;
    esac || {
        red "Nginx 安装失败。"
        return 1
    }

    start_and_enable_service nginx || return 1
    if nginx_available; then
        green "Nginx 安装完成。"
    else
        red "Nginx 命令仍不可用，请检查安装日志。"
        return 1
    fi
    ensure_nginx_app_conf_link
}

backup_manage_placeholder() {
    qiqi_section "备份管理"
    yellow "备份管理功能正在规划中。"
    muted "后续将在此提供备份浏览、恢复与清理等功能。"
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
    IMAGE_VERSION=""
    ACCESS_SCHEME=""
    ACCESS_HOST=""
    ACCESS_PORT=""
    ACCESS_PATH=""
    HEALTH_URL=""
    NGINX_TEMPLATE=""
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
            IMAGE_VERSION|IMAGE_VERSIONS) IMAGE_VERSION="$value" ;;
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

project_config_dir() {
    printf '%s/%s' "$(app_project_path "$1")" "$DNT_CONFIG_DIR_NAME"
}

dnt_state_dir() {
    printf '%s/%s' "$TARGET_BASE_DIR" "$DNT_STATE_DIR_NAME"
}

install_order_file() {
    printf '%s/install-order.tsv' "$(dnt_state_dir)"
}

install_order_seq_file() {
    printf '%s/install-order.seq' "$(dnt_state_dir)"
}

source_project_config_dir() {
    printf '%s/%s' "$(source_project_path "$1")" "$DNT_CONFIG_DIR_NAME"
}

project_has_template() {
    [ -f "$(source_project_path "$1")/docker-compose.yml" ]
}

project_files_exist() {
    [ -f "$(app_project_path "$1")/docker-compose.yml" ]
}

project_docker_container_ids() {
    local id="$1" path
    project_files_exist "$id" || return 0
    docker_available || return 0
    compose_cmd_available || return 0
    path="$(app_project_path "$id")"
    compose_run "$path" ps -a -q 2>/dev/null || true
}

project_is_installed() {
    [ -n "$(project_docker_container_ids "$1")" ]
}

project_runtime_path() {
    if project_files_exist "$1"; then
        app_project_path "$1"
    else
        source_project_path "$1"
    fi
}

project_conf_file() {
    local id="$1"
    if [ -f "$(project_config_dir "$id")/project.conf" ]; then
        printf '%s/project.conf' "$(project_config_dir "$id")"
    elif [ -f "$(app_project_path "$id")/project.conf" ]; then
        printf '%s/project.conf' "$(app_project_path "$id")"
    elif project_files_exist "$id"; then
        return 0
    elif [ -f "$(source_project_config_dir "$id")/project.conf" ]; then
        printf '%s/project.conf' "$(source_project_config_dir "$id")"
    elif [ -f "$(source_project_path "$id")/project.conf" ]; then
        printf '%s/project.conf' "$(source_project_path "$id")"
    fi
}

project_conf_file_for_write() {
    local id="$1" path
    path="$(project_config_dir "$id")"
    mkdir -p "$path"
    printf '%s/project.conf' "$path"
}

ensure_project_conf_file() {
    local id="$1" conf_file existing
    conf_file="$(project_conf_file_for_write "$id")"
    if [ ! -f "$conf_file" ]; then
        existing="$(project_conf_file "$id")"
        if [ -n "$existing" ] && [ "$existing" != "$conf_file" ]; then
            cp "$existing" "$conf_file"
        else
            write_project_conf_defaults "$id" "$conf_file"
        fi
    fi
    printf '%s' "$conf_file"
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
    conf_file="$(ensure_project_conf_file "$id")"
    quoted="$(quote_conf_value "$value")"
    tmp="$(mktemp)"
    awk -v key="$key" -v value="$quoted" '
        BEGIN { done=0; line=key "=\"" value "\"" }
        $0 ~ "^" key "=" { print line; done=1; next }
        { print }
        END { if (!done) print line }
    ' "$conf_file" > "$tmp"
    mv "$tmp" "$conf_file"
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
IMAGE_VERSION=""
HEALTH_URL="$health"
PUBLIC_URL=""
EOF
}

path_import_timestamp() {
    local path="$1" ts
    ts="$(stat -c '%W' "$path" 2>/dev/null || true)"
    case "$ts" in ''|*[!0-9]*|-*) ts="" ;; esac
    if [ -z "$ts" ] || [ "$ts" -le 0 ] 2>/dev/null; then
        ts="$(stat -f '%B' "$path" 2>/dev/null || true)"
        case "$ts" in ''|*[!0-9]*|-*) ts="" ;; esac
    fi
    if [ -z "$ts" ] || [ "$ts" -le 0 ] 2>/dev/null; then
        ts="$(stat -c '%Y' "$path" 2>/dev/null || stat -f '%m' "$path" 2>/dev/null || true)"
        case "$ts" in ''|*[!0-9]*|-*) ts="0" ;; esac
    fi
    printf '%s' "$ts"
}

list_source_project_ids() {
    local d id
    [ -d "$DOCKER_SOURCE_DIR" ] || return 0
    for d in "$DOCKER_SOURCE_DIR"/*; do
        [ -d "$d" ] || continue
        [ -f "$d/docker-compose.yml" ] || continue
        id="$(basename "$d")"
        printf '%s\t%s\n' "$(path_import_timestamp "$d")" "$id"
    done | LC_ALL=C sort -n -k1,1 -k2,2 | awk -F '\t' '{print $2}'
}

list_app_project_ids() {
    local d id
    [ -d "$TARGET_BASE_DIR" ] || return 0
    for d in "$TARGET_BASE_DIR"/*; do
        [ -d "$d" ] || continue
        [ -f "$d/docker-compose.yml" ] || continue
        id="$(basename "$d")"
        case "$id" in backup|backups|"$DNT_STATE_DIR_NAME") continue ;; esac
        printf '%s\t%s\n' "$(path_import_timestamp "$d")" "$id"
    done | LC_ALL=C sort -n -k1,1 -k2,2 | awk -F '\t' '{print $2}'
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

next_install_order() {
    local order_file seq_file max=0 value
    order_file="$(install_order_file)"
    seq_file="$(install_order_seq_file)"
    if [ -f "$seq_file" ]; then
        value="$(sed -n '1p' "$seq_file" 2>/dev/null || true)"
        case "$value" in ''|*[!0-9]*) ;; *) max="$value" ;; esac
    fi
    if [ -f "$order_file" ]; then
        while IFS=$'\t' read -r value _rest; do
            case "$value" in ''|*[!0-9]*) continue ;; esac
            [ "$value" -gt "$max" ] 2>/dev/null && max="$value"
        done < "$order_file"
    fi
    printf '%s' "$((max + 1))"
}

install_order_record_exists() {
    local id="$1" order_file
    order_file="$(install_order_file)"
    [ -f "$order_file" ] || return 1
    awk -F '\t' -v id="$id" '$2 == id { found=1; exit } END { exit !found }' "$order_file"
}

record_project_install_order() {
    local id="$1" order_file seq_file state_dir order now
    [ -n "$id" ] || return 0
    install_order_record_exists "$id" && return 0
    state_dir="$(dnt_state_dir)"
    order_file="$(install_order_file)"
    seq_file="$(install_order_seq_file)"
    mkdir -p "$state_dir" || return 1
    order="$(next_install_order)"
    now="$(date +"%Y-%m-%dT%H:%M:%S%z")"
    printf '%s\t%s\t%s\n' "$order" "$id" "$now" >> "$order_file"
    printf '%s\n' "$order" > "$seq_file"
}

remove_project_install_order() {
    local id="$1" order_file tmp
    order_file="$(install_order_file)"
    [ -f "$order_file" ] || return 0
    tmp="$(mktemp)"
    awk -F '\t' -v id="$id" '$2 != id { print }' "$order_file" > "$tmp"
    mv "$tmp" "$order_file"
}

cleanup_install_order_records() {
    local order_file tmp order id installed_at seen
    docker_available && compose_cmd_available || return 0
    order_file="$(install_order_file)"
    [ -f "$order_file" ] || return 0
    tmp="$(mktemp)"
    seen="|"
    while IFS=$'\t' read -r order id installed_at; do
        [ -n "$id" ] || continue
        case "$seen" in *"|$id|"*) continue ;; esac
        if project_is_installed "$id"; then
            printf '%s\t%s\t%s\n' "$order" "$id" "$installed_at"
            seen="${seen}${id}|"
        fi
    done < "$order_file" > "$tmp"
    mv "$tmp" "$order_file"
}

ordered_installed_ids_from_state() {
    local order_file id seen
    order_file="$(install_order_file)"
    [ -f "$order_file" ] || return 0
    seen="|"
    LC_ALL=C sort -n -k1,1 "$order_file" | while IFS=$'\t' read -r _order id _time; do
        [ -n "$id" ] || continue
        case "$seen" in *"|$id|"*) continue ;; esac
        project_is_installed "$id" && printf '%s\n' "$id"
        seen="${seen}${id}|"
    done
}

missing_installed_ids_from_state() {
    local id
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        project_is_installed "$id" || continue
        install_order_record_exists "$id" || printf '%s\n' "$id"
    done < <(list_project_ids)
}

collect_installed_ids() {
    local id index tmp_dir installed_file emitted_file order_file cleaned_file
    local probe_limit="${DN_TOOLS_PROBE_CONCURRENCY:-8}" active_probes=0
    local ids=() batch_pids=() probe_pid
    docker_available && compose_cmd_available || return 0
    case "$probe_limit" in ''|*[!0-9]*|0) probe_limit=8 ;; esac

    tmp_dir="$(mktemp -d)" || return 1
    installed_file="$tmp_dir/installed"
    emitted_file="$tmp_dir/emitted"
    : > "$installed_file"
    : > "$emitted_file"

    # 安装状态彼此独立，并发查询所有项目；旧实现会在清理顺序、读取顺序和查漏
    # 三个阶段重复执行 compose ps，项目越多等待越明显。
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        ids+=("$id")
        index="${#ids[@]}"
        (project_is_installed "$id" && printf '%s\n' "$id" > "$tmp_dir/$index.id") &
        batch_pids+=("$!")
        active_probes=$((active_probes + 1))
        if [ "$active_probes" -ge "$probe_limit" ]; then
            for probe_pid in "${batch_pids[@]}"; do
                wait "$probe_pid" 2>/dev/null || true
            done
            batch_pids=()
            active_probes=0
        fi
    done < <(list_project_ids)

    for probe_pid in "${batch_pids[@]}"; do
        wait "$probe_pid" 2>/dev/null || true
    done

    index=1
    while [ "$index" -le "${#ids[@]}" ]; do
        [ -f "$tmp_dir/$index.id" ] && cat "$tmp_dir/$index.id" >> "$installed_file"
        index=$((index + 1))
    done

    order_file="$(install_order_file)"
    if [ -f "$order_file" ]; then
        cleaned_file="$tmp_dir/install-order.tsv"
        awk -F '\t' '
            FILENAME == ARGV[1] { installed[$0]=1; next }
            installed[$2] && !seen[$2]++ { print }
        ' "$installed_file" "$order_file" > "$cleaned_file"
        mv "$cleaned_file" "$order_file"
        LC_ALL=C sort -n -k1,1 "$order_file" | awk -F '\t' 'NF >= 2 { print $2 }' > "$emitted_file"
    fi
    cat "$emitted_file"

    # 兼容旧版本已安装项目：没有顺序记录时，按项目目录导入时间补到队尾。
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        grep -Fqx -- "$id" "$emitted_file" && continue
        record_project_install_order "$id" || true
        printf '%s\n' "$id"
    done < "$installed_file"
    rm -rf "$tmp_dir"
}

copy_builtin_project_to_app() {
    local id="$1" mode="${2:-keep}" source_path target_path merge_keep=0
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
            yellow ">>> $target_path 已存在但尚无 docker-compose.yml，将补齐内置项目文件。"
            merge_keep=1
        else
            rm -rf "$target_path"
        fi
    fi

    mkdir -p "$TARGET_BASE_DIR" || return 1
    mkdir -p "$target_path" || return 1
    pink ">>> 正在复制内置项目到 $target_path"
    if [ "$merge_keep" -eq 1 ]; then
        cp -a -n "$source_path/." "$target_path/" || return 1
    else
        cp -a "$source_path/." "$target_path/" || return 1
    fi
    ensure_project_conf_file "$id" >/dev/null
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

detect_compose_command() {
    case "$DN_TOOLS_COMPOSE_KIND" in
        docker|standalone) return 0 ;;
        none) return 1 ;;
    esac

    if docker compose version >/dev/null 2>&1; then
        DN_TOOLS_COMPOSE_KIND="docker"
        return 0
    fi
    if command_exists docker-compose; then
        DN_TOOLS_COMPOSE_KIND="standalone"
        return 0
    fi
    DN_TOOLS_COMPOSE_KIND="none"
    return 1
}

compose_cmd_available() {
    detect_compose_command
}

compose_run() {
    local workdir="$1"
    shift
    detect_compose_command || {
        red "错误: 未检测到 docker compose 或 docker-compose。"
        return 127
    }
    if [ "$DN_TOOLS_COMPOSE_KIND" = "docker" ]; then
        (cd "$workdir" && docker compose "$@")
    else
        (cd "$workdir" && docker-compose "$@")
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
    if [ -n "$HEALTH_URL" ]; then
        printf '%s' "$HEALTH_URL"
        return 0
    fi
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

check_url_mark() {
    local url="$1"
    local connect_timeout="${DN_TOOLS_CHECK_CONNECT_TIMEOUT:-1}"
    local max_time="${DN_TOOLS_CHECK_MAX_TIME:-2}"
    if ! command_exists curl; then
        printf "?"
        return 0
    fi
    if [ -z "$url" ] || [ "$url" = "未识别" ] || [ "$url" = "未配置" ]; then
        printf "-"
        return 0
    fi
    if curl -fsS --connect-timeout "$connect_timeout" --max-time "$max_time" "$url" >/dev/null 2>&1; then
        printf "✅"
    else
        printf "❌"
    fi
}

check_url_icon() {
    local mark
    mark="$(check_url_mark "$1")"
    case "$mark" in
        ✅) printf "${QIQI_GREEN}%s${QIQI_PLAIN}" "$mark" ;;
        ❌) printf "${QIQI_RED}%s${QIQI_PLAIN}" "$mark" ;;
        *) printf "${QIQI_GRAY}%s${QIQI_PLAIN}" "$mark" ;;
    esac
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
    project_image_lines "$compose_file" | awk 'BEGIN { first=1 } { if (!first) printf ", "; printf "%s", $0; first=0 } END { if (!first) printf "\n" }'
}

project_image_lines() {
    local compose_file="$1"
    [ -f "$compose_file" ] || return 0
    awk '
        /^[[:space:]]*image:[[:space:]]*/ {
            sub(/^[^:]*:[[:space:]]*/, "")
            gsub(/[" ]/, "")
            print
        }
    ' "$compose_file"
}

record_project_image_versions() {
    local id="$1" compose_file versions
    compose_file="$(app_project_path "$id")/docker-compose.yml"
    [ -f "$compose_file" ] || return 0

    versions="$(project_images "$compose_file")"
    [ -n "$versions" ] || return 0
    set_project_conf_value "$id" "IMAGE_VERSION" "$versions"
}

project_running_status_text() {
    local id="$1" known_installed="${2:-0}" path ids running
    if ! project_files_exist "$id"; then
        printf "未安装"
        return 0
    fi
    if ! docker_available || ! compose_cmd_available; then
        printf "未检测"
        return 0
    fi
    path="$(app_project_path "$id")"
    if [ "$known_installed" = "1" ]; then
        ids="installed"
    else
        ids="$(compose_run "$path" ps -a -q 2>/dev/null || true)"
    fi
    running="$(compose_run "$path" ps --status running -q 2>/dev/null || true)"
    if [ -z "$ids" ]; then
        printf "未安装"
    elif [ -n "$running" ]; then
        printf "运行中"
    else
        printf "未完全运行"
    fi
}

project_running_status() {
    local status
    status="$(project_running_status_text "$1")"
    case "$status" in
        运行中) printf "${QIQI_GREEN}%s${QIQI_PLAIN}" "$status" ;;
        未完全运行) printf "${QIQI_ORANGE}%s${QIQI_PLAIN}" "$status" ;;
        *) printf "${QIQI_GRAY}%s${QIQI_PLAIN}" "$status" ;;
    esac
}

placeholder_files() {
    local path="$1"
    [ -d "$path" ] || return 0
    find "$path" -maxdepth 2 -type f \
        ! -name '*.example' \
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
    local conf_path p detected_dir=""
    if [ "$DN_TOOLS_NGINX_DIR_DETECTED" = "1" ]; then
        [ -n "$DN_TOOLS_NGINX_DIR_CACHE" ] && printf '%s' "$DN_TOOLS_NGINX_DIR_CACHE"
        return 0
    fi

    if [ -n "${NGINX_DIR_OVERRIDE:-}" ]; then
        DN_TOOLS_NGINX_DIR_CACHE="$NGINX_DIR_OVERRIDE"
        DN_TOOLS_NGINX_DIR_DETECTED=1
        printf '%s' "$DN_TOOLS_NGINX_DIR_CACHE"
        return 0
    fi

    if nginx_available; then
        conf_path="$(nginx -t 2>&1 | awk -F 'configuration file ' '/configuration file / {print $2; exit}' | awk '{print $1}')"
        if [ -z "$conf_path" ] || [ ! -f "$conf_path" ]; then
            conf_path="$(nginx -V 2>&1 | grep -o -E '\-\-conf-path=[^ ]+' | cut -d '=' -f 2)"
        fi
        if [ -n "$conf_path" ] && [ -f "$conf_path" ]; then
            detected_dir="$(dirname "$conf_path")"
        fi
    fi

    if [ -z "$detected_dir" ]; then
        for p in "/etc/nginx" "/usr/local/nginx/conf" "/opt/homebrew/etc/nginx"; do
            if [ -d "$p" ]; then
                detected_dir="$p"
                break
            fi
        done
    fi

    DN_TOOLS_NGINX_DIR_CACHE="$detected_dir"
    DN_TOOLS_NGINX_DIR_DETECTED=1
    [ -n "$DN_TOOLS_NGINX_DIR_CACHE" ] && printf '%s' "$DN_TOOLS_NGINX_DIR_CACHE"
}

nginx_project_conf() {
    local nginx_dir="$1" id="$2"
    printf '%s/conf.d/%s.conf' "$nginx_dir" "$id"
}

project_nginx_conf_file() {
    local id="$1" dir file
    for dir in "$(project_config_dir "$id")" "$(source_project_config_dir "$id")"; do
        [ -d "$dir" ] || continue
        for file in "$dir/$id.conf" "$dir/nginx.conf"; do
            [ -f "$file" ] && { printf '%s' "$file"; return 0; }
        done
        for file in "$dir"/*.conf; do
            [ -f "$file" ] || continue
            [ "$(basename "$file")" = "project.conf" ] && continue
            printf '%s' "$file"
            return 0
        done
    done
}

rotate_numbered_conf_backups() {
    local current_file="$1"
    [ -f "$current_file" ] || return 0

    rm -f "$current_file.bak3"
    [ -f "$current_file.bak2" ] && mv "$current_file.bak2" "$current_file.bak3"
    [ -f "$current_file.bak1" ] && mv "$current_file.bak1" "$current_file.bak2"
    mv "$current_file" "$current_file.bak1"
}

sync_nginx_conf_to_project() {
    local id="$1" conf_file="$2" backup_dir current_file
    [ -f "$conf_file" ] || {
        red "错误: Nginx 配置不存在，无法同步: $conf_file"
        return 1
    }

    backup_dir="$(project_config_dir "$id")"
    current_file="$backup_dir/$id.conf"
    mkdir -p "$backup_dir" || return 1

    if [ -f "$current_file" ] && cmp -s "$conf_file" "$current_file"; then
        muted "dntool-config 中的 Nginx 配置已是最新: $current_file"
        return 0
    fi

    rotate_numbered_conf_backups "$current_file" || return 1
    cp "$conf_file" "$current_file" || return 1
    green "已同步 Nginx 配置到: $current_file"
    muted "旧配置最多保留 3 份: $current_file.bak1 / .bak2 / .bak3"
}

sync_current_nginx_conf_to_project_if_changed() {
    local id="$1" nginx_dir conf_file
    nginx_dir="$(detect_nginx_dir)"
    [ -n "$nginx_dir" ] || return 0

    conf_file="$(nginx_project_conf "$nginx_dir" "$id")"
    [ -f "$conf_file" ] || return 0
    sync_nginx_conf_to_project "$id" "$conf_file"
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
    domain="$(awk '
        {
            for (i=1;i<=NF;i++) {
                if ($i == "server_name" && (i + 1) <= NF) {
                    domain=$(i + 1)
                    gsub(";", "", domain)
                    print domain
                    exit
                }
            }
        }
    ' "$conf")"
    listen_port="$(awk '
        /listen[[:space:]]+/ {
            port=""
            for (i=1;i<=NF;i++) {
                token=$i
                gsub(";", "", token)
                if (token ~ /^[0-9]+$/) {
                    port=token
                    break
                }
                if (token ~ /:[0-9]+$/) {
                    port=token
                    sub(/^.*:/, "", port)
                    break
                }
            }
            if (port == "") next
            if ($0 ~ /[[:space:]]ssl([[:space:];]|$)/) {
                print port
                done=1
                exit
            }
            if (first == "") first=port
        }
        END { if (!done && first != "") print first }
    ' "$conf")"
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

project_backup_file_for_timestamp() {
    local id="$1" timestamp="$2" backup_file index
    backup_file="$BACKUP_DIR/${id}-${timestamp}.tar.gz"
    if [ ! -e "$backup_file" ]; then
        printf '%s' "$backup_file"
        return 0
    fi

    index=2
    while [ -e "$BACKUP_DIR/${id}-${timestamp}-${index}.tar.gz" ]; do
        index=$((index + 1))
    done
    printf '%s' "$BACKUP_DIR/${id}-${timestamp}-${index}.tar.gz"
}

project_has_today_backup() {
    local id="$1" today
    today="$(date +"%Y%m%d")"
    [ -d "$BACKUP_DIR" ] || return 1
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "$id-${today}-*.tar.gz" -print -quit 2>/dev/null | grep -q .
}

backup_project_dir() {
    local id="$1" path timestamp backup_file count file
    path="$(app_project_path "$id")"
    [ -d "$path" ] || {
        red "错误: 项目未安装到 $path，无法备份。"
        return 1
    }
    sync_current_nginx_conf_to_project_if_changed "$id" || return 1
    mkdir -p "$BACKUP_DIR"
    timestamp="$(date +"%Y%m%d-%H%M")"
    backup_file="$(project_backup_file_for_timestamp "$id" "$timestamp")"
    pink ">>> 正在备份 $id 到 $backup_file"
    tar -zcf "$backup_file" -C "$(dirname "$path")" "$(basename "$path")" || return 1

    count=0
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        count=$((count + 1))
        if [ "$count" -gt 3 ]; then
            rm -f "$file"
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "$id-*.tar.gz" -exec ls -t {} + 2>/dev/null)
    green "备份完成: $backup_file"
}

backup_project_dir_for_update() {
    local id="$1" answer
    if project_has_today_backup "$id"; then
        yellow "检测到今天已有 $id 的更新备份。"
        readp "  今日已更新备份，是否再次备份？[y/N] → " answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            yellow "已跳过备份，仅执行更新。"
            return 0
        fi
    fi
    backup_project_dir "$id"
}

confirm_action() {
    local prompt="$1" answer
    readp "$prompt [y/N] → " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}
