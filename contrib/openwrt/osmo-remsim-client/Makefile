#
# Copyright (C) 2024 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=osmo-remsim-client
PKG_VERSION:=0.4.1
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/terminills/osmo-remsim.git
PKG_SOURCE_VERSION:=HEAD
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_MIRROR_HASH:=skip

PKG_MAINTAINER:=Osmocom <openbsc@lists.osmocom.org>
PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=COPYING

PKG_BUILD_PARALLEL:=1
PKG_INSTALL:=1
PKG_FIXUP:=autoreconf

include $(INCLUDE_DIR)/package.mk

define Package/osmo-remsim-client
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Telephony
  TITLE:=Osmocom Remote SIM - OpenWRT Client
  URL:=https://osmocom.org/projects/osmo-remsim
  DEPENDS:=+libosmocore +libosmo-netif +libosmo-gsm +libpthread +librt
endef

define Package/osmo-remsim-client/description
 osmo-remsim-client enables OpenWRT routers to use remote SIM cards through
 the remsim-server infrastructure. It provides:
 - Remote SIM card authentication and management
 - Support for multiple modems (Fibocom FM350-GL, 850L)
 - GPIO-based SIM slot switching
 - Integration with OpenWRT modem subsystem
 - KI (Authentication Key) proxy support
endef

define Package/osmo-remsim-client/conffiles
/etc/config/remsim
endef

CONFIGURE_ARGS += \
	--disable-remsim-server \
	--disable-remsim-bankd \
	--disable-client-st2 \
	--disable-manuals \
	--disable-pcsc \
	--enable-client-only \
	--prefix=/usr

TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include
TARGET_LDFLAGS += -L$(STAGING_DIR)/usr/lib

define Package/osmo-remsim-client/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/osmo-remsim-client-openwrt $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/osmo-remsim-client-shell $(1)/usr/bin/

	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libosmo-rspro.so* $(1)/usr/lib/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/remsim.config $(1)/etc/config/remsim

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/remsim.init $(1)/etc/init.d/remsim

	$(INSTALL_DIR) $(1)/usr/share/osmo-remsim
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/contrib/openwrt-event-script.sh $(1)/usr/share/osmo-remsim/
endef

define Package/osmo-remsim-client/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/remsim enable
	echo "osmo-remsim-client installed. Configure via /etc/config/remsim or LuCI interface."
}
exit 0
endef

define Package/osmo-remsim-client/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/remsim stop
	/etc/init.d/remsim disable
}
exit 0
endef

$(eval $(call BuildPackage,osmo-remsim-client))
