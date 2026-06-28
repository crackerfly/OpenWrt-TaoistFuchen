include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-taoistfuchen
PKG_VERSION:=1.3.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Hevil

LUCI_TITLE:=Taoist Fuchen - Custom Logo, FakeHTTP and FakeSIP
LUCI_DESCRIPTION:=A LuCI toolbox that replaces the Web UI favicon/logo and provides web settings for the bundled FakeHTTP (TCP-over-HTTP) and FakeSIP (UDP-over-SIP) DPI-evasion tools.

# NOTE on dependencies:
#  * kmod-nft-queue provides the NFQUEUE kernel module that FakeHTTP/FakeSIP need
#    and is NOT part of the base system, so it is a real dependency.
#  * nftables (the 'nft' userspace) is required at runtime too, BUT it is already
#    part of every standard OpenWrt install (it is the firewall4 backend). It is
#    therefore intentionally NOT listed here: declaring it could let a package
#    manager remove the firewall backend when this app is uninstalled. Leaving it
#    out guarantees uninstalling this app can never touch nftables.
LUCI_DEPENDS:=+luci-base +kmod-nft-queue

# NOTE: This package bundles prebuilt native (aarch64) binaries for FakeHTTP
# and FakeSIP, so it is architecture-specific. Do NOT mark it as "all".
# With LUCI_PKGARCH unset the package inherits the target architecture, i.e.
# it must be built with the aarch64 / mt7622 SDK for the Linksys E8450.

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

# Remove ONLY our log-cleanup cron entry. The cron service, nftables and any
# other shared component are left untouched.
if [ -f /etc/crontabs/root ]; then
	sed -i '\#taoistfuchen/logclean#d' /etc/crontabs/root 2>/dev/null || true
	/etc/init.d/cron restart >/dev/null 2>&1 || true
fi

# Tidy up the in-RAM log files.
rm -f /tmp/fakehttp.log /tmp/fakesip.log 2>/dev/null || true

exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
