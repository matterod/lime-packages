include $(TOPDIR)/rules.mk

PKG_NAME:=lime-watchcat

GIT_COMMIT_DATE:=$(shell git log -n 1 --pretty=%ad --date=short . )
GIT_COMMIT_TSTAMP:=$(shell git log -n 1 --pretty=%at . )

PKG_VERSION=$(GIT_COMMIT_DATE)-$(GIT_COMMIT_TSTAMP)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	TITLE:= Watchcat integration and default configuration for LibreMesh
	CATEGORY:= LibreMesh
	URL:=https://libremesh.org
	DEPENDS:=+watchcat +luci-app-watchcat
endef

define Package/$(PKG_NAME)/description
				This package integrates OpenWrt's watchcat into LibreMesh.
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
endef

$(eval $(call BuildPackage, $(PKG_NAME)))
