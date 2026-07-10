#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# GitHub's web uploader does not preserve the executable bit. Restore every
# file that must execute either in CI or on the router before cp -a imports the
# package tree into the SDK.
chmod 0755 \
	"$ROOT"/tests/*.sh \
	"$ROOT"/scripts/*.sh \
	"$ROOT"/scripts/*.py \
	"$ROOT"/luci-app-taoistfuchen/root/etc/init.d/* \
	"$ROOT"/luci-app-taoistfuchen/root/etc/hotplug.d/iface/99-taoistfuchen \
	"$ROOT"/luci-app-taoistfuchen/root/etc/uci-defaults/99_taoistfuchen \
	"$ROOT"/luci-app-taoistfuchen/root/usr/bin/fakehttp \
	"$ROOT"/luci-app-taoistfuchen/root/usr/bin/fakesip \
	"$ROOT"/luci-app-taoistfuchen/root/www/cgi-bin/taoistfuchen-upload

echo "source executable permissions normalized"
