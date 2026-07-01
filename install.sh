#!/usr/bin/env bash
export LANG=en_US.UTF-8

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/DN_Tools}"
BIN_PATH="${BIN_PATH:-/usr/local/bin/dntool}"
REPO_URL="${REPO_URL:-https://github.com/qiqi-style/DN_Tools.git}"
RAW_MODE=0

case "$INSTALL_DIR" in
    ""|"/")
        echo "错误: INSTALL_DIR 不能是空值或根目录。"
        exit 1
        ;;
esac

case "$BIN_PATH" in
    ""|"/")
        echo "错误: BIN_PATH 不能是空值或根目录。"
        exit 1
        ;;
esac

if [ -f "$SOURCE_DIR/scripts/theme.sh" ]; then
    # shellcheck source=scripts/theme.sh
    . "$SOURCE_DIR/scripts/theme.sh"
else
    # theme.sh 是可选增强。缺失时使用高对比 fallback，确保安装脚本仍可运行。
    QIQI_PINK='\033[38;5;161m'
    QIQI_GREEN='\033[38;5;34m'
    QIQI_ORANGE='\033[38;5;166m'
    QIQI_RED='\033[38;5;160m'
    QIQI_PLAIN='\033[0m'
    pink(){ printf "${QIQI_PINK}%s${QIQI_PLAIN}\n" "$1"; }
    green(){ printf "${QIQI_GREEN}%s${QIQI_PLAIN}\n" "$1"; }
    yellow(){ printf "${QIQI_ORANGE}%s${QIQI_PLAIN}\n" "$1"; }
    red(){ printf "${QIQI_RED}%s${QIQI_PLAIN}\n" "$1"; }
    qiqi_line(){ printf "${QIQI_PINK}%s${QIQI_PLAIN}\n" "────────────────────────────────────────────────────────"; }
fi

if [ "$EUID" -ne 0 ]; then
    red "错误: 请使用 sudo/root 运行安装脚本。"
    echo "示例: sudo bash install.sh"
    exit 1
fi

qiqi_line
pink "          正在安装 DN_Tools Docker / Nginx 运维控制台"
qiqi_line

if [ ! -f "$SOURCE_DIR/start.sh" ] || [ ! -d "$SOURCE_DIR/scripts" ]; then
    RAW_MODE=1
fi

if [ "$RAW_MODE" -eq 1 ]; then
    pink ">>> 检测到远程一键安装模式，准备同步 GitHub 仓库..."
    if ! command -v git >/dev/null 2>&1; then
        yellow ">>> 未检测到 git，正在尝试安装基础依赖..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -y -qq >/dev/null 2>&1 || true
            apt-get install -y -qq git curl wget >/dev/null 2>&1 || true
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q git curl wget >/dev/null 2>&1 || true
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y -q git curl wget >/dev/null 2>&1 || true
        fi
    fi

    if ! command -v git >/dev/null 2>&1; then
        red "错误: Git 不可用，请先安装 git 后重试。"
        exit 1
    fi

    tmp_dir="${INSTALL_DIR}.tmp.$$"
    rm -rf "$tmp_dir"
    mkdir -p "$(dirname "$INSTALL_DIR")"
    pink ">>> 正在重新拉取 $REPO_URL 到 $INSTALL_DIR"
    git clone "$REPO_URL" "$tmp_dir" >/dev/null 2>&1 || {
        red "错误: 拉取仓库失败，已保留现有安装目录。"
        rm -rf "$tmp_dir"
        exit 1
    }
    rm -rf "$INSTALL_DIR"
    mv "$tmp_dir" "$INSTALL_DIR"
elif [ "$SOURCE_DIR" != "$INSTALL_DIR" ]; then
    tmp_dir="${INSTALL_DIR}.tmp.$$"
    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"
    pink ">>> 正在复制项目文件到 $INSTALL_DIR"
    cp -a "$SOURCE_DIR/." "$tmp_dir/"
    rm -rf "$INSTALL_DIR"
    mv "$tmp_dir" "$INSTALL_DIR"
else
    pink ">>> 当前已位于安装目录，跳过复制。"
fi

pink ">>> 正在配置脚本权限"
chmod +x "$INSTALL_DIR/start.sh" "$INSTALL_DIR/install.sh" "$INSTALL_DIR"/scripts/*.sh

write_launcher() {
    local path="$1"
    local project_url install_cmd delete_cmd
    project_url="https://github.com/qiqi-style/DN_Tools"
    install_cmd='bash <(curl -sL https://raw.githubusercontent.com/qiqi-style/DN_Tools/main/install.sh)'
    delete_cmd="sudo rm -f $path"
    cat > "$path" << EOF
#!/usr/bin/env bash
INSTALL_DIR="$INSTALL_DIR"
PROJECT_URL="$project_url"
INSTALL_CMD="$install_cmd"
DELETE_CMD="$delete_cmd"

if [ ! -f "\$INSTALL_DIR/start.sh" ]; then
    echo "错误: DN_Tools 脚本目录不存在或不完整: \$INSTALL_DIR"
    echo
    echo "项目地址: \$PROJECT_URL"
    echo "重新拉取 / 安装命令:"
    echo "  \$INSTALL_CMD"
    echo "删除当前 dntool 命令:"
    echo "  \$DELETE_CMD"
    exit 1
fi

if [ "\$EUID" -ne 0 ]; then
    cd "\$INSTALL_DIR" && sudo ./start.sh
else
    cd "\$INSTALL_DIR" && ./start.sh
fi
EOF
    chmod +x "$path"
}

pink ">>> 正在写入全局命令"
write_launcher "$BIN_PATH"

green "安装完成。以后可以运行: dntool"
yellow "提示: Docker/Nginx 自动安装当前仍为占位功能，请先按服务器环境安装依赖。"

if [ "${DN_TOOLS_NO_AUTO_START:-0}" = "1" ]; then
    yellow "已跳过自动启动（DN_TOOLS_NO_AUTO_START=1）。"
    exit 0
fi

if { [ -r /dev/tty ] && [ -w /dev/tty ] && : < /dev/tty; } 2>/dev/null; then
    pink ">>> 正在启动 DN_Tools 控制台..."
    sleep 1
    "$BIN_PATH" < /dev/tty
else
    yellow "当前环境没有可用 TTY，请手动运行: dntool"
fi
