# Managed by openwrt-console. Enable/disable from LuCI, not by deleting this file.
case "$-" in
    *i*)
        if [ -t 0 ] && [ -t 1 ] &&
           [ "$(id -u 2>/dev/null)" = 0 ] &&
           [ -z "${OPENWRT_CONSOLE_ACTIVE:-}" ] &&
           [ "$(cat /etc/openwrt-console/login-enabled 2>/dev/null)" = 1 ] &&
           [ -x /usr/sbin/openwrt-console ]; then
            OPENWRT_CONSOLE_ACTIVE=1 /usr/sbin/openwrt-console
        fi
        ;;
esac
