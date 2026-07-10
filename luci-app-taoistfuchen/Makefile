include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-taoistfuchen
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE COPYING
PKG_MAINTAINER:=Hevil

# The package contains upstream static AArch64 binaries.  An explicit LuCI
# architecture is required; without it luci.mk classifies a pure LuCI package
# as "all", which would allow installation on incompatible targets.
LUCI_PKGARCH:=aarch64_cortex-a53

LUCI_TITLE:=Taoist Fuchen - Custom Logo, FakeHTTP and FakeSIP
LUCI_DESCRIPTION:=Router-oriented LuCI settings for Custom Logo and the bundled FakeHTTP/FakeSIP DPI-obfuscation helpers.

LUCI_DEPENDS:=+luci-base +cgi-io +nftables +kmod-nft-queue +coreutils-stat +coreutils-od

# Preserve all three UCI databases across apk/opkg package upgrades so that the
# uci-defaults migration can transform existing 1.x values in place.
define Package/$(PKG_NAME)/conffiles
/etc/config/taoistfuchen
/etc/config/fakehttp
/etc/config/fakesip
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -z "$$IPKG_INSTROOT" ] || exit 0

# Stop and disable the three services this app manages.
for svc in taoistfuchen fakehttp fakesip; do
	if [ -x /etc/init.d/$$svc ]; then
		/etc/init.d/$$svc stop >/dev/null 2>&1 || true
		/etc/init.d/$$svc disable >/dev/null 2>&1 || true
	fi
done

# Remove the legacy 1.x cron line without changing the cron service itself.
if [ -f /etc/crontabs/root ]; then
	sed -i '\#taoistfuchen/logclean#d' /etc/crontabs/root 2>/dev/null || true
fi

# Best-effort cleanup for a killed or crashed upstream process. Shared nftables
# packages and unrelated tables are never removed.
for family in ip ip6; do
	nft delete table "$$family" fakehttp >/dev/null 2>&1 || true
	nft delete table "$$family" fakesip  >/dev/null 2>&1 || true
done

rm -f /tmp/fakehttp.log /tmp/fakesip.log \
	/tmp/fakehttp.bootwait /tmp/fakesip.bootwait 2>/dev/null || true
rm -rf /var/run/taoistfuchen-upload \
	/www/luci-static/taoistfuchen/customlogo 2>/dev/null || true

exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
