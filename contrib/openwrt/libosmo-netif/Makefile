#
# Copyright (C) 2024 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=libosmo-netif
PKG_VERSION:=1.6.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/osmocom/libosmo-netif.git
PKG_SOURCE_VERSION:=$(PKG_VERSION)
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_MIRROR_HASH:=skip

PKG_MAINTAINER:=Osmocom <openbsc@lists.osmocom.org>
PKG_LICENSE:=GPL-2.0 LGPL-3.0
PKG_LICENSE_FILES:=COPYING

PKG_BUILD_PARALLEL:=1
PKG_INSTALL:=1
PKG_FIXUP:=autoreconf

include $(INCLUDE_DIR)/package.mk

define Package/libosmo-netif
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=Osmocom network interface library
  URL:=https://osmocom.org/projects/libosmo-netif
  DEPENDS:=+libosmocore +libosmo-gsm +libpthread
endef

define Package/libosmo-netif/description
  libosmo-netif is a library providing various network interface
  utilities for Osmocom projects, including IPA, LAPD, and stream support.
endef

CONFIGURE_ARGS += \
	--disable-doxygen \
	--disable-libsctp \
	--disable-manuals \
	--prefix=/usr

TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include
TARGET_LDFLAGS += -L$(STAGING_DIR)/usr/lib

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include/osmocom
	$(CP) $(PKG_INSTALL_DIR)/usr/include/osmocom/netif $(1)/usr/include/osmocom/
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libosmonetif.so* $(1)/usr/lib/
	$(INSTALL_DIR) $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/libosmo-netif.pc $(1)/usr/lib/pkgconfig/
endef

define Package/libosmo-netif/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libosmonetif.so* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,libosmo-netif))
