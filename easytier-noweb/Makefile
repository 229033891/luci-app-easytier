include $(TOPDIR)/rules.mk
-include $(dir $(lastword $(MAKEFILE_LIST)))../version.mk

PKG_NAME:=easytier-noweb
PKG_VERSION:=$(or $(EASYTIER_VERSION),2.7.9)

ifeq ($(ARCH),mipsel)
	APP_ARCH:=mipsel
endif
ifeq ($(ARCH),mips)
	APP_ARCH:=mips
endif
ifeq ($(ARCH),arm)
	APP_ARCH:=arm
endif
ifeq ($(BOARD),kirkwood)
	APP_ARCH:=arm
endif
ifeq ($(ARCH),armv7)
	APP_ARCH:=armv7
endif
ifeq ($(ARCH),aarch64)
	APP_ARCH:=aarch64
endif
ifeq ($(ARCH),arm64)
	APP_ARCH:=aarch64
endif
ifeq ($(ARCH),armv8)
	APP_ARCH:=aarch64
endif
ifeq ($(ARCH),x86_64)
	APP_ARCH:=x86_64
endif

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	TITLE:=A simple, decentralized mesh VPN with WireGuard support.
	DEPENDS:=@(x86_64||arm||aarch64||mipsel||mips) +kmod-tun
	URL:=https://github.com/229033891/EasyTier
	MENU:=1
endef

define Package/$(PKG_NAME)/description
  A simple, decentralized mesh VPN with WireGuard support (no web console).
  Installs Release-aligned binaries: ET-core, ET-cli.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	if [ ! -f $(PKG_BUILD_DIR)/ET-core ]; then \
		wget https://github.com/229033891/EasyTier/releases/download/v$(PKG_VERSION)/ET-linux-$(APP_ARCH)-v$(PKG_VERSION).zip -O $(PKG_BUILD_DIR)/easytier-$(PKG_VERSION).zip; \
		unzip -o -j $(PKG_BUILD_DIR)/easytier-$(PKG_VERSION).zip -d $(PKG_BUILD_DIR); \
		rm -f $(PKG_BUILD_DIR)/easytier-$(PKG_VERSION).zip; \
	fi
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(CP) $(PKG_BUILD_DIR)/ET-core $(1)/usr/bin/
	chmod 0755 $(1)/usr/bin/ET-core
	$(CP) $(PKG_BUILD_DIR)/ET-cli $(1)/usr/bin/
	chmod 0755 $(1)/usr/bin/ET-cli
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
if [ -f /etc/config/easytier ]; then
	_core=$$(uci -q get easytier.@easytier[0].easytierbin)
	case "$$_core" in
		""|/usr/bin/easytier-core|/tmp/easytier-core)
			uci -q set easytier.@easytier[0].easytierbin=/usr/bin/ET-core
			;;
	esac
	uci -q commit easytier
fi
rm -f /usr/bin/easytier-core /usr/bin/easytier-cli 2>/dev/null || true
exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
