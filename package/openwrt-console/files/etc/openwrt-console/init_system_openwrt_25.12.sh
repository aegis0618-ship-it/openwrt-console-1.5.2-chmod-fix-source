#!/bin/sh
# OpenWrt 25.12 / Linux 6.12 system console (BusyBox ash compatible)

if [ -t 1 ]; then
    RED=$(printf '\033[0;31m')
    GREEN=$(printf '\033[0;32m')
    YELLOW=$(printf '\033[1;33m')
    BLUE=$(printf '\033[0;34m')
    CYAN=$(printf '\033[0;36m')
    NC=$(printf '\033[0m')
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    NC=''
fi

info() { printf '%s%s%s\n' "$BLUE" "$*" "$NC"; }
ok() { printf '%s%s%s\n' "$GREEN" "$*" "$NC"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$NC"; }
error() { printf '%s%s%s\n' "$RED" "$*" "$NC" >&2; }

clear_screen() {
    if [ -t 1 ]; then
        if command -v clear >/dev/null 2>&1; then
            clear
        else
            printf '\033[2J\033[H'
        fi
    fi
}

pause_menu() {
    printf '\n按回车键返回主菜单...'
    IFS= read -r _dummy
}

confirm() {
    _message=$1
    printf '%s [y/N]: ' "$_message"
    IFS= read -r _answer || return 1
    case $_answer in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

is_valid_ipv4() {
    _ip=$1
    [ -n "$_ip" ] || return 1
    case $_ip in *[!0-9.]*) return 1 ;; esac
    _old_ifs=$IFS
    IFS=.
    set -- $_ip
    IFS=$_old_ifs
    [ "$#" -eq 4 ] || return 1
    for _octet do
        case $_octet in
            ''|*[!0-9]*) return 1 ;;
            0|[1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]) ;;
            *) return 1 ;;
        esac
    done
}

root_password_is_set() {
    [ -r /etc/shadow ] || return 0
    _hash=$(awk -F: '$1 == "root" { print $2; exit }' /etc/shadow 2>/dev/null)
    case $_hash in
        ''|'!'*|'*'*) return 1 ;;
        *) return 0 ;;
    esac
}

check_root_password() {
    root_password_is_set && return 0
    warn 'root 尚未设置有效密码。'
    command -v passwd >/dev/null 2>&1 || { error '未找到 passwd 命令。'; return 1; }
    passwd root || return 1
    root_password_is_set || { error 'root 密码仍未设置。'; return 1; }
}

modify_ipv4() {
    command -v uci >/dev/null 2>&1 || { error '未找到 uci 命令。'; return 1; }
    _current=$(uci -q get network.lan.ipaddr 2>/dev/null)
    printf '当前 UCI LAN 地址：%s\n' "${_current:-未设置或由 DHCP 获取}"
    printf '请输入新的 LAN IPv4 地址：'
    IFS= read -r _ip || return 1
    [ -n "$_ip" ] || { warn '输入为空，已取消。'; return 0; }
    is_valid_ipv4 "$_ip" || { error 'IPv4 地址格式无效。'; return 1; }
    warn '修改后网络会重启，当前 SSH 连接可能断开。'
    confirm "确认将 network.lan.ipaddr 设置为 $_ip 吗？" || { warn '已取消。'; return 0; }
    uci set "network.lan.ipaddr=$_ip" && uci commit network || {
        error '配置写入失败，网络未重启。'
        return 1
    }
    ok '配置已提交，2 秒后重启网络。'
    (sleep 2; /etc/init.d/network restart) >/dev/null 2>&1 &
}

ping_test() {
    command -v ping >/dev/null 2>&1 || { error '未找到 ping 命令。'; return 1; }
    printf '请输入目标主机或 IP（默认 openwrt.org）：'
    IFS= read -r _target || return 1
    [ -n "$_target" ] || _target=openwrt.org
    case $_target in -*|*' '*|*'	'*) error '目标不能以短横线开头或包含空白。'; return 1 ;; esac
    info "正在 ping $_target（4 次）..."
    ping -c 4 -W 2 "$_target"
}

clear_memory() {
    sync
    if [ -w /proc/sys/vm/drop_caches ]; then
        printf '3\n' > /proc/sys/vm/drop_caches || { error '清理缓存失败。'; return 1; }
        ok '文件系统缓存已请求释放；Linux 会按需重新建立缓存。'
    else
        warn '内核未提供可写的 drop_caches，未执行清理。'
    fi
    if command -v free >/dev/null 2>&1; then
        free -m 2>/dev/null || free
    fi
}

factory_reset() {
    error '高危操作：恢复出厂会删除 overlay 中的配置和安装内容。'
    confirm '确定继续恢复出厂设置吗？' || { warn '已取消。'; return 0; }
    printf '再次确认，请输入大写 ERASE：'
    IFS= read -r _confirm || return 1
    [ "$_confirm" = ERASE ] || { warn '输入不匹配，已取消。'; return 1; }

    if command -v factoryreset >/dev/null 2>&1; then
        factoryreset -y || { error 'factoryreset 执行失败。'; return 1; }
    elif command -v jffs2reset >/dev/null 2>&1; then
        jffs2reset -y || { error 'jffs2reset 执行失败。'; return 1; }
    elif command -v firstboot >/dev/null 2>&1; then
        firstboot -y || { error 'firstboot 执行失败。'; return 1; }
    else
        error '未找到 factoryreset、jffs2reset 或 firstboot。'
        return 1
    fi
    warn '恢复出厂指令已执行，设备即将重启。'
    sleep 2
    reboot
}

reboot_device() {
    confirm '确定重启设备吗？' && reboot
}

shutdown_device() {
    confirm '确定关闭设备吗？' || return 0
    if command -v poweroff >/dev/null 2>&1; then
        poweroff
    elif command -v halt >/dev/null 2>&1; then
        halt
    else
        error '未找到 poweroff 或 halt 命令。'
        return 1
    fi
}

get_lan_ipv4() {
    _addr=$(ip -4 addr show br-lan 2>/dev/null | awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}')
    [ -n "$_addr" ] || _addr=$(uci -q get network.lan.ipaddr 2>/dev/null)
    printf '%s' "${_addr:-未获取}"
}

print_text_menu() {
    clear_screen
    _hostname=$(uci -q get system.@system[0].hostname 2>/dev/null)
    [ -n "$_hostname" ] || _hostname=$(hostname 2>/dev/null)
    _model=$(cat /tmp/sysinfo/model 2>/dev/null | tr -d '\000\r')
    [ -n "$_model" ] || _model=未知
    _version=$(awk -F= '$1 == "DISTRIB_DESCRIPTION" {gsub(/^"|"$/, "", $2); print $2; exit}' /etc/openwrt_release 2>/dev/null)
    [ -n "$_version" ] || _version=$(awk -F= '$1 == "DISTRIB_RELEASE" {gsub(/^"|"$/, "", $2); print $2; exit}' /etc/openwrt_release 2>/dev/null)
    [ -n "$_version" ] || _version=未知
    _cpu_model=$(awk -F: '
        /^[ \t]*(model name|Processor|Hardware)[ \t]*:/ {
            sub(/^[ \t]+/, "", $2)
            if ($2 != "") { print $2; exit }
        }
    ' /proc/cpuinfo 2>/dev/null)
    [ -n "$_cpu_model" ] || _cpu_model=$(uname -m 2>/dev/null)
    _ip=$(get_lan_ipv4)
    _uptime=$(awk '{
        n = int($1)
        printf "%dd %02dh %02dm", n/86400, (n%86400)/3600, (n%3600)/60
    }' /proc/uptime 2>/dev/null)
    _mem_total=$(awk '/MemTotal:/ {printf "%.0f MB", $2/1024}' /proc/meminfo 2>/dev/null)
    _mem_available=$(awk '
        /MemAvailable:/ {v=$2}
        END {
            if (v == "") {
                while ((getline line < "/proc/meminfo") > 0)
                    if (line ~ /^MemFree:/) {split(line, a); v=a[2]; break}
            }
            if (v != "") printf "%.0f MB", v/1024
        }
    ' /proc/meminfo 2>/dev/null)
    _storage=$(df -h /overlay 2>/dev/null | awk 'NR==2 {print $3 " / " $2}')
    [ -n "$_storage" ] || _storage=未知

    printf '%s' "$CYAN"
    cat <<'LOGO'
   ____                   _       _  __ _
  / __ \____  ___ _ __   | |     | |/ /| |
 / / / / __ \/ _ \ '_ \  | |     | ' / | |
/ /_/ / /_/ /  __/ | | | | |___  | . \ | |
\____/ .___/\___|_| |_| |_____|  |_|\_\|_|
    /_/
LOGO
    printf '%s' "$NC"
    printf '%s\n' '                    OpenWrt System Console'
    printf '%s\n' '========================================================================'
    printf '%s设备状态 (Device Status)%s\n' "$GREEN" "$NC"
    printf '  主机名 (Hostname)    : %s\n' "${_hostname:-未知}"
    printf '  型号 (Model)         : %s\n' "$_model"
    printf '  CPU 信息 (CPU Info)  : %s\n' "${_cpu_model:-未知}"
    printf '  版本 (Version)       : %s\n' "$_version"
    printf '  架构 (Architecture)  : %s\n' "$(uname -m 2>/dev/null)"
    printf '  LAN IPv4 地址        : %s\n' "$_ip"
    printf '  运行时间 (Uptime)    : %s\n' "${_uptime:-未知}"
    printf '  可用内存 (Available) : %s / %s\n' "${_mem_available:-未知}" "${_mem_total:-未知}"
    printf '  存储 (Storage)       : %s\n' "$_storage"
    if root_password_is_set; then
        printf '  Root 密码 (Password) : %s已设置 (Set)%s\n' "$GREEN" "$NC"
    else
        printf '  Root 密码 (Password) : %s未设置 (Not Set)%s\n' "$RED" "$NC"
    fi
    printf '%s\n' '========================================================================'
    printf '%s快捷菜单 (Quick Menu)%s\n' "$BLUE" "$NC"
    printf '  1. 修改 IPv4 地址 (Change IPv4 Address)\n'
    printf '  2. 设置 Root 密码 (Set Root Password)\n'
    printf '  3. 恢复出厂设置 (Factory Reset)\n'
    printf '  4. 重启设备 (Reboot)\n'
    printf '  5. 关机 (Shutdown)\n'
    printf '  6. 网络连通性测试 (Ping Test)\n'
    printf '  7. 清理缓存 (Clear Memory)\n'
    printf '  8. 刷新状态 (Refresh Status)\n'
    printf '  9. 退出菜单 (Exit)\n'
    printf '%s\n' '------------------------------------------------------------------------'
}

[ "$(id -u 2>/dev/null)" = 0 ] || { error '请以 root 身份运行。'; exit 1; }

while :; do
    print_text_menu
    printf '请输入选项 [1-9]：'
    IFS= read -r _choice || break
    case $_choice in
        1) modify_ipv4; pause_menu ;;
        2) passwd root; pause_menu ;;
        3) factory_reset; pause_menu ;;
        4) reboot_device; pause_menu ;;
        5) shutdown_device; pause_menu ;;
        6) ping_test; pause_menu ;;
        7) clear_memory; pause_menu ;;
        8) : ;;
        9) ok '已退出控制台。'; break ;;
        *) error '无效选项，请输入 1 到 9。'; pause_menu ;;
    esac
done
