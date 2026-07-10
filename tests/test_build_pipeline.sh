#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MINIMIZER="$ROOT/scripts/minimize-sdk-config.awk"
COLLECTOR="$ROOT/scripts/prepare-artifact.sh"
VERIFIER="$ROOT/scripts/verify-built-apk.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

for required in "$MINIMIZER" "$COLLECTOR" "$VERIFIER"; do
	if [ ! -f "$required" ]; then
		echo "missing build pipeline file: $required" >&2
		exit 1
	fi
done

cat > "$TMP/Config-build.in" <<'EOF'
config PACKAGE_unrelated_module
	tristate
	default m

config PACKAGE_unrelated_builtin
	bool
	default y

config PACKAGE_kmod-lib-crc32c
	bool
	default m

config PACKAGE_kmod-nfnetlink-queue
	tristate
	default y

config PACKAGE_conditional
	tristate
	default m if ALL
EOF

awk -f "$MINIMIZER" "$TMP/Config-build.in" > "$TMP/Config-build.min.in"

default_for() {
	awk -v wanted="$1" '
		$1 == "config" { package = $2 }
		package == wanted && $1 == "default" { print $2; exit }
	' "$TMP/Config-build.min.in"
}

[ "$(default_for PACKAGE_unrelated_module)" = "n" ]
[ "$(default_for PACKAGE_unrelated_builtin)" = "n" ]
[ "$(default_for PACKAGE_kmod-lib-crc32c)" = "y" ]
[ "$(default_for PACKAGE_kmod-nfnetlink-queue)" = "m" ]
grep -Fqx '	default m if ALL' "$TMP/Config-build.min.in"

SDK="$TMP/openwrt-sdk"
mkdir -p "$SDK/bin/packages/aarch64_cortex-a53/base" \
	"$SDK/bin/targets/mediatek/mt7622/packages" \
	"$SDK/staging_dir/host/bin"

MAIN_APK="$SDK/bin/packages/aarch64_cortex-a53/base/luci-app-taoistfuchen-2.0.0-r2.apk"
touch "$MAIN_APK" \
	"$SDK/bin/packages/aarch64_cortex-a53/base/coreutils-stat-9.9-r2.apk" \
	"$SDK/bin/packages/aarch64_cortex-a53/base/nftables-nojson-1.1.6-r2.apk" \
	"$SDK/bin/targets/mediatek/mt7622/packages/kmod-nft-queue-6.12.94-r1.apk"

cat > "$SDK/staging_dir/host/bin/apk" <<'EOF'
#!/bin/sh
cat <<'META'
info:
  name: luci-app-taoistfuchen
  version: 2.0.0-r2
  description: test
  arch: aarch64_cortex-a53
  license: MIT GPL-3.0-or-later
  maintainer: Hevil
  url: https://github.com/crackerfly/OpenWrt-TaoistFuchen
  depends: # 7 items
    - cgi-io
    - coreutils-od
    - coreutils-stat
    - kmod-nft-queue
    - libc
    - luci-base
    - nftables
  provides: # 1 items
    - luci-app-taoistfuchen-any
META
EOF
chmod 0755 "$SDK/staging_dir/host/bin/apk"

sh "$COLLECTOR" "$SDK" "$TMP/output-one"

[ "$(find "$TMP/output-one" -maxdepth 1 -type f -name '*.apk' | wc -l)" -eq 1 ]
[ -f "$TMP/output-one/$(basename "$MAIN_APK")" ]
! find "$TMP/output-one" -maxdepth 1 -type f \( \
	-name 'kmod-*.apk' -o -name 'nftables-*.apk' -o -name 'coreutils-*.apk' \
	\) | grep -q .
[ -f "$TMP/output-one/THIRD_PARTY_SOURCES.md" ]
[ -f "$TMP/output-one/FakeHTTP-0.9.18.tar.gz" ]
[ -f "$TMP/output-one/FakeSIP-Droid-MAX-0.9.3.tar.gz" ]
[ -f "$TMP/output-one/SHA256SUMS" ]

touch "$SDK/bin/packages/aarch64_cortex-a53/base/luci-app-taoistfuchen-2.0.0-r2-duplicate.apk"
if sh "$COLLECTOR" "$SDK" "$TMP/output-duplicate" >"$TMP/duplicate.log" 2>&1; then
	echo "artifact collector accepted multiple application APKs" >&2
	exit 1
fi
grep -Fq 'expected exactly one luci-app-taoistfuchen-*.apk' "$TMP/duplicate.log"

echo "build pipeline tests: ok"
