#!/usr/bin/env bash
export LANG=en_US.UTF-8

# ==============================================================================
# qiqi-style shared terminal theme
# ==============================================================================
#
# 使用方式：
#
#   # 推荐：脚本中先判断文件存在，再 source。没有 theme.sh 时使用自己的 fallback，
#   # 不要让主题文件成为脚本运行的硬依赖。
#   if [ -f "$TOOL_ROOT/theme.sh" ]; then
#       # shellcheck source=theme.sh
#       . "$TOOL_ROOT/theme.sh"
#   else
#       pink(){ printf '%s\n' "$1"; }
#       green(){ printf '%s\n' "$1"; }
#       yellow(){ printf '%s\n' "$1"; }
#       red(){ printf '%s\n' "$1"; }
#       muted(){ printf '%s\n' "$1"; }
#   fi
#
#   qiqi_banner "DN_Tools" "v1.0.0" "Docker / Nginx 运维工具" "https://github.com/qiqi-style/DN_Tools"
#   qiqi_section "功能菜单"
#   qiqi_menu_item "1" "Docker 项目安装"
#   readp "请输入选项 → " choice
#
# 主题模式：
#
#   QIQI_THEME_MODE=auto     # 默认。优先读取 COLORFGBG，无法判断时使用 contrast。
#   QIQI_THEME_MODE=contrast # 高对比配色，浅色/暗色背景都尽量清楚。
#   QIQI_THEME_MODE=light    # 明色终端背景，使用更深的绿色/青色/粉色。
#   QIQI_THEME_MODE=dark     # 暗色终端背景，使用更亮的霓虹色。
#   QIQI_THEME_MODE=plain    # 无颜色输出，适合日志、CI 或不支持 ANSI 的终端。
#
# 关闭颜色：
#
#   NO_COLOR=1 ./start.sh
#   QIQI_THEME_MODE=plain ./start.sh
#
# 可覆盖链接：
#
#   QIQI_GITHUB_URL=https://github.com/xxx ./start.sh
#
# ==============================================================================

QIQI_GITHUB_URL="${QIQI_GITHUB_URL:-https://github.com/qiqi-style}"
QIQI_YOUTUBE_URL="${QIQI_YOUTUBE_URL:-https://www.youtube.com/@qiqi-style}"
QIQI_BLOG_URL="${QIQI_BLOG_URL:-https://qiaiai.xyz}"
QIQI_THEME_MODE="${QIQI_THEME_MODE:-auto}"
QIQI_BANNER_STYLE="${QIQI_BANNER_STYLE:-full}"

qiqi_color_enabled() {
    [ -z "${NO_COLOR:-}" ] || return 1
    [ "${QIQI_THEME_MODE}" != "plain" ] || return 1
    [ "${QIQI_THEME_MODE}" != "none" ] || return 1
    [ "${TERM:-}" != "dumb" ] || return 1
    return 0
}

qiqi_detect_theme_mode() {
    local mode="$QIQI_THEME_MODE" bg
    case "$mode" in
        light|dark|contrast|plain|none) printf '%s' "$mode"; return 0 ;;
    esac

    # COLORFGBG 通常形如 "15;0" 或 "0;15"，最后一段是背景色编号。
    # 0-6/8 视作暗背景，7/9-15 视作亮背景。许多终端不会设置它，
    # 因此无法判断时回退到 contrast，避免浅色背景看不清。
    if [ -n "${COLORFGBG:-}" ]; then
        bg="${COLORFGBG##*;}"
        case "$bg" in
            ''|*[!0-9]*) ;;
            0|1|2|3|4|5|6|8) printf 'dark'; return 0 ;;
            *) printf 'light'; return 0 ;;
        esac
    fi

    printf 'contrast'
}

qiqi_ansi_256() {
    if qiqi_color_enabled; then
        printf '\033[38;5;%sm' "$1"
    fi
}

qiqi_ansi_bold() {
    if qiqi_color_enabled; then
        printf '\033[1m'
    fi
}

QIQI_EFFECTIVE_THEME="$(qiqi_detect_theme_mode)"

if qiqi_color_enabled; then
    QIQI_PLAIN='\033[0m'
    QIQI_BOLD="$(qiqi_ansi_bold)"

    case "$QIQI_EFFECTIVE_THEME" in
        dark)
            QIQI_PINK="$(qiqi_ansi_256 211)"
            QIQI_PINK_2="$(qiqi_ansi_256 213)"
            QIQI_GREEN="$(qiqi_ansi_256 118)"
            QIQI_GREEN_2="$(qiqi_ansi_256 157)"
            QIQI_ORANGE="$(qiqi_ansi_256 208)"
            QIQI_CYAN="$(qiqi_ansi_256 81)"
            QIQI_GRAY="$(qiqi_ansi_256 250)"
            QIQI_WHITE="$(qiqi_ansi_256 255)"
            QIQI_RED="$(qiqi_ansi_256 203)"
            QIQI_LOGO_1="$(qiqi_ansi_256 211)"
            QIQI_LOGO_2="$(qiqi_ansi_256 213)"
            QIQI_LOGO_3="$(qiqi_ansi_256 214)"
            QIQI_LOGO_4="$(qiqi_ansi_256 118)"
            QIQI_LOGO_5="$(qiqi_ansi_256 120)"
            QIQI_LOGO_6="$(qiqi_ansi_256 157)"
            ;;
        light)
            QIQI_PINK="$(qiqi_ansi_256 161)"
            QIQI_PINK_2="$(qiqi_ansi_256 162)"
            QIQI_GREEN="$(qiqi_ansi_256 28)"
            QIQI_GREEN_2="$(qiqi_ansi_256 34)"
            QIQI_ORANGE="$(qiqi_ansi_256 130)"
            QIQI_CYAN="$(qiqi_ansi_256 25)"
            QIQI_GRAY="$(qiqi_ansi_256 240)"
            QIQI_WHITE="$(qiqi_ansi_256 235)"
            QIQI_RED="$(qiqi_ansi_256 124)"
            QIQI_LOGO_1="$(qiqi_ansi_256 161)"
            QIQI_LOGO_2="$(qiqi_ansi_256 162)"
            QIQI_LOGO_3="$(qiqi_ansi_256 166)"
            QIQI_LOGO_4="$(qiqi_ansi_256 28)"
            QIQI_LOGO_5="$(qiqi_ansi_256 34)"
            QIQI_LOGO_6="$(qiqi_ansi_256 30)"
            ;;
        *)
            # 默认高对比方案：不用荧光绿/纯白，避免浅色主题下文字发糊。
            QIQI_PINK="$(qiqi_ansi_256 161)"
            QIQI_PINK_2="$(qiqi_ansi_256 162)"
            QIQI_GREEN="$(qiqi_ansi_256 34)"
            QIQI_GREEN_2="$(qiqi_ansi_256 35)"
            QIQI_ORANGE="$(qiqi_ansi_256 166)"
            QIQI_CYAN="$(qiqi_ansi_256 31)"
            QIQI_GRAY="$(qiqi_ansi_256 244)"
            QIQI_WHITE="$(qiqi_ansi_256 245)"
            QIQI_RED="$(qiqi_ansi_256 160)"
            QIQI_LOGO_1="$(qiqi_ansi_256 161)"
            QIQI_LOGO_2="$(qiqi_ansi_256 162)"
            QIQI_LOGO_3="$(qiqi_ansi_256 166)"
            QIQI_LOGO_4="$(qiqi_ansi_256 34)"
            QIQI_LOGO_5="$(qiqi_ansi_256 35)"
            QIQI_LOGO_6="$(qiqi_ansi_256 37)"
            ;;
    esac
else
    QIQI_PINK=''
    QIQI_PINK_2=''
    QIQI_GREEN=''
    QIQI_GREEN_2=''
    QIQI_ORANGE=''
    QIQI_CYAN=''
    QIQI_GRAY=''
    QIQI_WHITE=''
    QIQI_RED=''
    QIQI_PLAIN=''
    QIQI_BOLD=''
    QIQI_LOGO_1=''
    QIQI_LOGO_2=''
    QIQI_LOGO_3=''
    QIQI_LOGO_4=''
    QIQI_LOGO_5=''
    QIQI_LOGO_6=''
fi

# qiqi-style 配色语义：
# - 粉色：品牌主色、分隔线、输入提示
# - 绿色：成功状态、可执行菜单编号、健康服务
# - 橙色：警告、默认值、需要注意的配置
# - 青色：项目名、模块名、重点信息
# - 灰色：次要说明、未配置状态、辅助文本
# - 红色：错误、危险操作

pink(){ printf "${QIQI_PINK}%s${QIQI_PLAIN}\n" "$1"; }
green(){ printf "${QIQI_GREEN}%s${QIQI_PLAIN}\n" "$1"; }
yellow(){ printf "${QIQI_ORANGE}%s${QIQI_PLAIN}\n" "$1"; }
red(){ printf "${QIQI_RED}%s${QIQI_PLAIN}\n" "$1"; }
cyan(){ printf "${QIQI_CYAN}%s${QIQI_PLAIN}\n" "$1"; }
muted(){ printf "${QIQI_GRAY}%s${QIQI_PLAIN}\n" "$1"; }

readp() {
    local prompt="$1"
    local __var="$2"
    if { [ -r /dev/tty ] && [ -w /dev/tty ] && : < /dev/tty; } 2>/dev/null; then
        IFS='' read -r -p "$(printf "${QIQI_PINK}%s${QIQI_PLAIN}" "$prompt")" "$__var" < /dev/tty
    else
        IFS='' read -r -p "$(printf "${QIQI_PINK}%s${QIQI_PLAIN}" "$prompt")" "$__var"
    fi
}

pause() {
    local prompt="${1:-按回车键继续...}"
    local _pause_dummy
    readp "$prompt" _pause_dummy
}

qiqi_line() {
    printf "${QIQI_PINK}%s${QIQI_PLAIN}\n" "────────────────────────────────────────────────────────────────────────"
}

qiqi_section() {
    local title="$1"
    printf "\n${QIQI_PINK}───────────────────── %s ─────────────────────${QIQI_PLAIN}\n" "$title"
}

qiqi_menu_item() {
    local num="$1"
    local label="$2"
    local desc="${3:-}"
    if [ -n "$desc" ]; then
        printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN}  ${QIQI_WHITE}%s${QIQI_PLAIN} ${QIQI_GRAY}%s${QIQI_PLAIN}\n" "$num" "$label" "$desc"
    else
        printf "  ${QIQI_GREEN}[ %s ]${QIQI_PLAIN}  ${QIQI_WHITE}%s${QIQI_PLAIN}\n" "$num" "$label"
    fi
}

qiqi_banner() {
    local project_name="${1:-DN_Tools}"
    local version="${2:-v1.0.0}"
    local description="${3:-Docker / Nginx deployment toolkit}"
    local project_url="${4:-https://github.com/qiqi-style/DN_Tools}"

    echo
    if [ "$QIQI_BANNER_STYLE" = "compact" ] || [ "$QIQI_EFFECTIVE_THEME" = "plain" ] || [ "$QIQI_EFFECTIVE_THEME" = "none" ]; then
        qiqi_line
        printf "  ${QIQI_CYAN}%s${QIQI_PLAIN} ${QIQI_GRAY}%s${QIQI_PLAIN}\n" "$project_name" "$version"
        printf "  %s\n" "$description"
        qiqi_line
    else
        printf "${QIQI_PINK}  %s${QIQI_PLAIN}\n" "░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░"
        echo
        printf "  ${QIQI_LOGO_1} ██████╗  ${QIQI_LOGO_2}██╗${QIQI_LOGO_2} ██████╗  ${QIQI_LOGO_3}██╗         ${QIQI_LOGO_4}███████╗${QIQI_LOGO_5}████████╗${QIQI_LOGO_5}██╗   ██╗${QIQI_LOGO_6}██╗     ███████╗${QIQI_PLAIN}\n"
        printf "  ${QIQI_LOGO_1}██╔═══██╗ ${QIQI_LOGO_2}██║${QIQI_LOGO_2}██╔═══██╗ ${QIQI_LOGO_3}██║         ${QIQI_LOGO_4}██╔════╝${QIQI_LOGO_5}╚══██╔══╝${QIQI_LOGO_5}╚██╗ ██╔╝${QIQI_LOGO_6}██║     ██╔════╝${QIQI_PLAIN}\n"
        printf "  ${QIQI_LOGO_2}██║   ██║ ${QIQI_LOGO_2}██║${QIQI_LOGO_3}██║   ██║ ${QIQI_LOGO_3}██║  ▄▄▄▄▄  ${QIQI_LOGO_4}██║        ${QIQI_LOGO_5}██║    ╚████╔╝ ${QIQI_LOGO_6}██║     █████╗${QIQI_PLAIN}\n"
        printf "  ${QIQI_LOGO_2}██║   ██║ ${QIQI_LOGO_3}██║${QIQI_LOGO_3}██║   ██║ ${QIQI_LOGO_3}██║  ▀▀▀▀▀  ${QIQI_LOGO_4}███████╗   ${QIQI_LOGO_5}██║     ╚██╔╝  ${QIQI_LOGO_6}██║     ██╔══╝${QIQI_PLAIN}\n"
        printf "  ${QIQI_LOGO_3}██║▄▄ ██║ ${QIQI_LOGO_3}██║${QIQI_LOGO_3}██║▄▄ ██║ ${QIQI_LOGO_3}██║         ${QIQI_LOGO_5}╚════██║   ██║      ██║   ${QIQI_LOGO_6}██║     ██║${QIQI_PLAIN}\n"
        printf "  ${QIQI_LOGO_3}╚██████╔╝ ${QIQI_LOGO_3}██║${QIQI_LOGO_3}╚██████╔╝ ${QIQI_LOGO_3}██║         ${QIQI_LOGO_5}███████║   ██║      ██║   ${QIQI_LOGO_6}███████╗███████╗${QIQI_PLAIN}\n"
        printf "  ${QIQI_LOGO_3} ╚══▀▀═╝  ╚═╝ ╚══▀▀═╝  ╚═╝         ${QIQI_LOGO_5}╚══════╝   ╚═╝      ╚═╝   ${QIQI_LOGO_6}╚══════╝╚══════╝${QIQI_PLAIN}\n"
        echo
        printf "${QIQI_GREEN}  %s${QIQI_PLAIN}\n" "░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░"
    fi

    echo
    printf "  ${QIQI_GREEN}⬥ qiqi Github   :${QIQI_PLAIN}  ${QIQI_WHITE}%s${QIQI_PLAIN}\n" "$QIQI_GITHUB_URL"
    printf "  ${QIQI_GREEN}⬥ qiqi YouTube  :${QIQI_PLAIN}  ${QIQI_WHITE}%s${QIQI_PLAIN}\n" "$QIQI_YOUTUBE_URL"
    printf "  ${QIQI_GREEN}⬥ qiqi 博客     :${QIQI_PLAIN}  ${QIQI_WHITE}%s${QIQI_PLAIN}\n" "$QIQI_BLOG_URL"
    printf "${QIQI_PINK}  ─────────────────────────── 项目简介 ─────────────────────────────  ${QIQI_PLAIN}\n"
    printf "  ${QIQI_GRAY}⬥${QIQI_PLAIN} 项目地址：${QIQI_CYAN}%s${QIQI_PLAIN}\n" "$project_url"
    printf "  ${QIQI_GRAY}⬥${QIQI_PLAIN} 当前版本：${QIQI_CYAN}%s (%s)${QIQI_PLAIN}\n" "$version" "$project_name"
    printf "  ${QIQI_GRAY}⬥${QIQI_PLAIN} ${QIQI_WHITE}%s${QIQI_PLAIN}\n" "$description"
}
