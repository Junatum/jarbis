# SPDX-License-Identifier: GPL-3.0-or-later
include $(TOPDIR)/rules.mk

PKG_NAME:=jarbis
PKG_VERSION:=0.1.0
PKG_RELEASE:=5
PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=SmartSafeHub Contributors
PKGARCH:=all
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/jarbis
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Jarbis - SmartSafeHub home automation core
  URL:=https://github.com/Junatum/jarbis
  DEPENDS:=+rpcd-mod-ucode +ucode-mod-uci +ucode-mod-fs +mosquitto-client-ssl +mosquitto-ssl +uclient-fetch +jsonfilter
endef

define Package/jarbis/description
 Lightweight Tasmota MQTT control with managed broker and on-demand discovery.
 Mosquitto is the only resident service; Jarbis has no polling daemon.
endef

define Package/jarbis/conffiles
/etc/config/jarbis
/etc/jarbis/mosquitto_pub
/etc/jarbis/mosquitto_sub
/etc/jarbis/device-credentials
/etc/mosquitto/jarbis.passwd
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./LICENSE $(PKG_BUILD_DIR)/LICENSE
endef

define Build/Compile
endef

define Package/jarbis/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/jarbis $(1)/etc/config/jarbis
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./root/usr/libexec/jarbis-control $(1)/usr/libexec/jarbis-control
	$(INSTALL_BIN) ./root/usr/libexec/jarbis-broker $(1)/usr/libexec/jarbis-broker
	$(INSTALL_BIN) ./root/usr/libexec/jarbis-discover $(1)/usr/libexec/jarbis-discover
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/jarbis $(1)/etc/init.d/jarbis
	$(INSTALL_BIN) ./root/usr/libexec/jarbis-rpcd-reconcile $(1)/usr/libexec/jarbis-rpcd-reconcile
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode/jarbis
	$(INSTALL_DATA) ./root/usr/share/rpcd/ucode/jarbis.uc $(1)/usr/share/rpcd/ucode/jarbis.uc
	$(INSTALL_DATA) ./root/usr/share/rpcd/ucode/jarbis/core.uc $(1)/usr/share/rpcd/ucode/jarbis/core.uc
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/jarbis.json $(1)/usr/share/rpcd/acl.d/jarbis.json
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./root/lib/upgrade/keep.d/jarbis $(1)/lib/upgrade/keep.d/jarbis
endef

define Package/jarbis/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	[ ! -x /etc/init.d/jarbis ] || /etc/init.d/jarbis enable
	if [ -x /etc/init.d/rpcd ]; then
		/bin/sh /usr/libexec/jarbis-rpcd-reconcile || exit 1
	fi
	[ "`uci -q get jarbis.main.enabled 2>/dev/null`" != 1 ] || /etc/init.d/jarbis start || exit 1
fi
exit 0
endef

define Package/jarbis/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ] && [ -x /etc/init.d/rpcd ]; then
	# rpcd will be reloaded by package manager on install/upgrade or next restart.
	:
fi
exit 0
endef

$(eval $(call BuildPackage,jarbis))
