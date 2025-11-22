#
# Copyright (C) 2024 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Support for osmo-remsim-client
LUCI_DEPENDS:=+osmo-remsim-client +luci-base
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-remsim
PKG_VERSION:=0.4.1
PKG_RELEASE:=1

PKG_MAINTAINER:=Osmocom <openbsc@lists.osmocom.org>
PKG_LICENSE:=GPL-2.0

include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-remsim/description
 LuCI web interface for osmo-remsim-client. Provides a user-friendly
 web-based configuration and monitoring interface for Remote SIM functionality
 on OpenWRT routers.
 
 Features:
 - Server connection configuration
 - Client identification settings
 - Modem configuration (single or dual-modem setup)
 - IonMesh orchestration integration
 - Real-time status monitoring
 - Advanced debugging options
endef

define Package/luci-app-remsim/conffiles
/etc/config/remsim
endef

define Package/luci-app-remsim/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/rpcd restart
}
exit 0
endef

# call BuildPackage - OpenWrt buildroot signature
