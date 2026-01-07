#
# Copyright (C) 2024 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=talloc
PKG_VERSION:=2.4.2
MAJOR_VERSION:=2
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://www.samba.org/ftp/talloc
PKG_HASH:=85ecf9e465e20f98f9950a52e9a411e14320bc555fa257d87697b7e7a9b1d8a6

PKG_MAINTAINER:=Osmocom <openbsc@lists.osmocom.org>
PKG_LICENSE:=LGPL-3.0-or-later
PKG_LICENSE_FILES:=COPYING

PKG_BUILD_PARALLEL:=0
PKG_BUILD_DEPENDS:=python3/host

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/kernel.mk

define Package/libtalloc
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=Core memory allocator used in Samba
  DEPENDS:=+libattr
  URL:=https://talloc.samba.org/talloc/doc/html/index.html
endef

define Package/libtalloc/description
  talloc is a hierarchical, reference counted memory pool system with destructors.
  It is the core memory allocator used in Samba.
endef

CROSS = " \
	\nChecking simple C program: \"hello world\" \
	\nrpath library support: (127, \"\") \
	\n-Wl,--version-script support: (127, \"\") \
	\nChecking getconf LFS_CFLAGS: NO \
	\nChecking for large file support without additional flags: OK \
	\nChecking correct behavior of strtoll: OK \
	\nChecking for working strptime: NO \
	\nChecking for C99 vsnprintf: \"1\" \
	\nChecking for HAVE_SHARED_MMAP: NO \
	\nChecking for HAVE_MREMAP: NO \
	\nChecking for HAVE_INCOHERENT_MMAP: (2, \"\") \
	\nChecking for HAVE_IMMEDIATE_STRUCTURES: OK \
	\nChecking for HAVE_MKDIR_MODE: OK \
	\nChecking for member st_rdev in struct stat: OK \
	\nChecking for member ss_family in struct sockaddr_storage: OK \
	\nChecking for member __ss_family in struct sockaddr_storage: NO \
	\nChecking for member sa_len in struct sockaddr: NO \
	\nChecking for member sin_len in struct sockaddr_in: NO \
	\nChecking for member sin6_len in struct sockaddr_in6: NO \
	\nChecking for HAVE_UNIXSOCKET: OK \
	\nChecking for HAVE_SECURE_MKSTEMP: OK \
	\nChecking for HAVE_IFACE_GETIFADDRS: OK \
	\nChecking for HAVE_IFACE_AIX: NO \
	\nChecking for HAVE_IFACE_IFCONF: OK \
	\nChecking for HAVE_IFACE_IFREQ: OK \
	\nChecking for declaration of getpwent_r: NO \
	\nChecking for declaration of getpwent_r (as enum): NO \
	\nChecking for declaration of getgrent_r: NO \
	\nChecking for declaration of getgrent_r (as enum): NO \
	\nChecking for strerror_r: OK \
	\nChecking for XSI (rather than GNU) prototype for strerror_r: OK \
	\nChecking for program 'xsltproc': NO \
	\nChecking for header sys/auxv.h: OK \
	\nChecking for getauxval: OK \
	\nChecking if compiler accepts -fstack-protector-strong: NO \
	\nChecking if compiler accepts -fstack-protector: NO \
	\nChecking if compiler accepts -fstack-clash-protection: OK \
	\n"

define Build/Configure
	(cd $(PKG_BUILD_DIR); \
		printf >cache.txt $(CROSS) " \
			\nChecking uname machine type: \"$(ARCH)\" \
			\nChecking uname release type: \"$(LINUX_VERSION)\" \
			\nChecking uname sysname type: \"Linux\" \
			\nChecking uname version type: \"$(LINUX_UNAME_VERSION)\" \
		\n" ; \
		$(CONFIGURE_VARS) \
		PYTHONHASHSEED=1 \
		./buildtools/bin/waf configure \
			--prefix=/usr \
			--sysconfdir=/etc \
			--localstatedir=/var \
			--cross-compile \
			--cross-answers=cache.txt \
			--disable-python \
			--disable-rpath \
			--disable-rpath-install \
	)
endef

define Build/Compile
	(cd $(PKG_BUILD_DIR); \
		./buildtools/bin/waf build -j$(shell nproc) -v \
	)
endef

define Build/Install
	(cd $(PKG_BUILD_DIR); \
		./buildtools/bin/waf install --destdir=$(PKG_INSTALL_DIR) \
	)
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_BUILD_DIR)/bin/default/libtalloc.so* $(1)/usr/lib/
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_BUILD_DIR)/talloc.h $(1)/usr/include/
	$(INSTALL_DIR) $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_BUILD_DIR)/bin/default/talloc.pc $(1)/usr/lib/pkgconfig/
endef

define Package/libtalloc/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_BUILD_DIR)/bin/default/libtalloc.so.$(MAJOR_VERSION)* $(1)/usr/lib/
	(cd $(1)/usr/lib; ln -sf libtalloc.so.$(MAJOR_VERSION) libtalloc.so)
endef

$(eval $(call BuildPackage,libtalloc))
