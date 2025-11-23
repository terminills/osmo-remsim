#
# Copyright (C) 2024 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=libosmocore
PKG_VERSION:=1.11.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/osmocom/libosmocore.git
PKG_SOURCE_VERSION:=1.11.0
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_MIRROR_HASH:=skip

PKG_MAINTAINER:=Osmocom <openbsc@lists.osmocom.org>
PKG_LICENSE:=GPL-2.0 LGPL-3.0
PKG_LICENSE_FILES:=COPYING

PKG_BUILD_PARALLEL:=1
PKG_INSTALL:=1
PKG_FIXUP:=autoreconf

include $(INCLUDE_DIR)/package.mk

define Package/libosmocore
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=Osmocom core library
  URL:=https://osmocom.org/projects/libosmocore
  DEPENDS:=+libtalloc +libpthread +librt
endef

define Package/libosmocore/description
  libosmocore is a library with various utility functions shared between
  OpenBSC / OpenNodeB and related Osmocom projects.
endef

define Package/libosmo-gsm
  $(call Package/libosmocore)
  TITLE:=Osmocom GSM library
  DEPENDS:=+libosmocore
endef

define Package/libosmo-gsm/description
  GSM specific utilities from libosmocore.
endef

CONFIGURE_ARGS += \
	--disable-doxygen \
	--disable-libsctp \
	--disable-libmnl \
	--disable-liburing \
	--disable-gnutls \
	--disable-pcsc \
	--disable-libusb \
	--disable-manuals \
	--prefix=/usr

TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include
TARGET_LDFLAGS += -L$(STAGING_DIR)/usr/lib

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include/osmocom
	$(CP) $(PKG_INSTALL_DIR)/usr/include/osmocom/* $(1)/usr/include/osmocom/
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libosmo*.so* $(1)/usr/lib/
	$(INSTALL_DIR) $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/libosmo*.pc $(1)/usr/lib/pkgconfig/
endef

define Package/libosmocore/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libosmocore.so* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libosmovty.so* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libosmoctrl.so* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libosmocoding.so* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libosmosim.so* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libosmousb.so* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libosmoisdn.so* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libosmogb.so* $(1)/usr/lib/
endef

define Package/libosmo-gsm/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libosmogsm.so* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,libosmocore))
$(eval $(call BuildPackage,libosmo-gsm))
