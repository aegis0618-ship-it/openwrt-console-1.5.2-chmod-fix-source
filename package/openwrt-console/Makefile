include $(TOPDIR)/rules.mk

PKG_NAME:=openwrt-console
PKG_VERSION:=1.5.2
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=OpenWrt Console

include $(INCLUDE_DIR)/package.mk

define Package/openwrt-console
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=LuCI editor and SSH login console
  PKGARCH:=all
  DEPENDS:=+busybox +luci-base +luci-compat
endef

define Package/openwrt-console/description
  Edit init_system_openwrt_25.12.sh in LuCI and optionally run it
  when root logs in through an interactive terminal.
endef

define Package/openwrt-console/conffiles
/etc/openwrt-console/init_system_openwrt_25.12.sh
/etc/openwrt-console/login-enabled
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/openwrt-console/install
	$(CP) ./files/* $(1)/
	chmod 0755 $(1)/usr/sbin/openwrt-console
	chmod 0644 $(1)/etc/profile.d/99-openwrt-console.sh
	chmod 0644 $(1)/etc/openwrt-console/*
endef

define Package/openwrt-console/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
# Remove only the marked background-boot hook installed by versions 1.3.x.
# Never execute the edited menu script during installation.
if grep -q '^# >>> OPENWRT_CONSOLE_STARTUP$$' /etc/rc.local 2>/dev/null; then
    if grep -q '^# <<< OPENWRT_CONSOLE_STARTUP$$' /etc/rc.local; then
        if cp -p /etc/rc.local /etc/rc.local.before-console-1.4.bak; then
            sed '/^# >>> OPENWRT_CONSOLE_STARTUP$$/,/^# <<< OPENWRT_CONSOLE_STARTUP$$/d' \
                /etc/rc.local > /etc/rc.local.console-new
            if /bin/sh -n /etc/rc.local.console-new; then
                cat /etc/rc.local.console-new > /etc/rc.local
            fi
            rm -f /etc/rc.local.console-new
        fi
    fi
fi
rm -f /tmp/luci-indexcache*
exit 0
endef

$(eval $(call BuildPackage,openwrt-console))
