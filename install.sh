#!/usr/bin/env bash
export LANG=en_US.UTF-8

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/DN_Tools}"
BIN_PATH="${BIN_PATH:-/usr/local/bin/dntool}"
REPO_URL="${REPO_URL:-https://github.com/qiqi-style/DN_Tools.git}"
RAW_MODE=0

if [ -f "$SOURCE_DIR/theme.sh" ]; then
    # shellcheck source=theme.sh
    . "$SOURCE_DIR/theme.sh"
else
    QIQI_PINK='\033[38;5;211m'
    QIQI_GREEN='\033[38;5;118m'
    QIQI_ORANGE='\033[38;5;208m'
    QIQI_PLAIN='\033[0m'
    pink(){ printf "${QIQI_PINK}%s${QIQI_PLAIN}\n" "$1"; }
    green(){ printf "${QIQI_GREEN}%s${QIQI_PLAIN}\n" "$1"; }
    yellow(){ printf "${QIQI_ORANGE}%s${QIQI_PLAIN}\n" "$1"; }
    red(){ printf "${QIQI_PINK}%s${QIQI_PLAIN}\n" "$1"; }
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

    if [ -d "$INSTALL_DIR/.git" ]; then
        pink ">>> 检测到已安装目录，正在更新 $INSTALL_DIR"
        git -C "$INSTALL_DIR" fetch --all >/dev/null 2>&1
        git -C "$INSTALL_DIR" reset --hard origin/main >/dev/null 2>&1
    else
        tmp_dir="${INSTALL_DIR}.tmp.$$"
        rm -rf "$tmp_dir"
        mkdir -p "$(dirname "$INSTALL_DIR")"
        pink ">>> 正在克隆 $REPO_URL 到 $INSTALL_DIR"
        git clone "$REPO_URL" "$tmp_dir" >/dev/null 2>&1
        rm -rf "$INSTALL_DIR"
        mv "$tmp_dir" "$INSTALL_DIR"
    fi
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
chmod +x "$INSTALL_DIR/start.sh" "$INSTALL_DIR/install.sh" "$INSTALL_DIR/theme.sh" "$INSTALL_DIR"/scripts/*.sh

write_launcher() {
    local path="$1"
    cat > "$path" << EOF
#!/usr/bin/env bash
if [ "\$EUID" -ne 0 ]; then
    cd "$INSTALL_DIR" && sudo ./start.sh
else
    cd "$INSTALL_DIR" && ./start.sh
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
