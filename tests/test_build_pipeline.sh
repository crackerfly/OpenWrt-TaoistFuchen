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
	"$SDK/staging_dir/host/bin" \
	"$TMP/bin"

python3 - "$TMP/fakesip.fixture" <<'PY'
import sys
from pathlib import Path

payload = bytearray(64)
payload[:6] = b"\x7fELF\x02\x01"
payload[18:20] = (183).to_bytes(2, "little")
payload.extend(
    b"/lib/ld-musl-aarch64.so.1\0"
    b"FakeSIP version 0.9.4\0"
    b"icmpv6 type time-exceeded counter drop\0"
)
Path(sys.argv[1]).write_bytes(payload)
PY

cat > "$TMP/bin/readelf" <<'EOF'
#!/bin/sh
cat <<'DYNAMIC'
 0x0000000000000001 (NEEDED) Shared library: [libnetfilter_queue.so.1]
 0x0000000000000001 (NEEDED) Shared library: [libnfnetlink.so.0]
 0x0000000000000001 (NEEDED) Shared library: [libmnl.so.0]
 0x0000000000000001 (NEEDED) Shared library: [libgcc_s.so.1]
 0x0000000000000001 (NEEDED) Shared library: [libc.so]
DYNAMIC
EOF
chmod 0755 "$TMP/bin/readelf"

MAIN_APK="$SDK/bin/packages/aarch64_cortex-a53/base/luci-app-taoistfuchen-2.1.0-r2.apk"
touch "$MAIN_APK" \
	"$SDK/bin/packages/aarch64_cortex-a53/base/coreutils-stat-9.9-r2.apk" \
	"$SDK/bin/packages/aarch64_cortex-a53/base/nftables-nojson-1.1.6-r2.apk" \
	"$SDK/bin/targets/mediatek/mt7622/packages/kmod-nft-queue-6.12.94-r1.apk"

cat > "$SDK/staging_dir/host/bin/apk" <<'EOF'
#!/bin/sh
for argument in "$@"; do
	if [ "$argument" = adbdump ]; then
cat <<'META'
info:
  name: luci-app-taoistfuchen
  version: 2.1.0-r2
  description: test
  arch: aarch64_cortex-a53
  license: MIT GPL-3.0-or-later
  maintainer: Hevil
  url: https://github.com/crackerfly/OpenWrt-TaoistFuchen
  depends: # 8 items
    - cgi-io
    - coreutils-od
    - coreutils-stat
    - kmod-nft-queue
    - libc
    - libnetfilter-queue1
    - luci-base
    - nftables
  provides: # 1 items
    - luci-app-taoistfuchen-any
META
		exit 0
	fi
done

destination=''
while [ "$#" -gt 0 ]; do
	if [ "$1" = --destination ]; then
		shift
		destination="$1"
	fi
	shift
done
[ -n "$destination" ]
mkdir -p "$destination/usr/bin"
cp "$FAKE_APK_BINARY" "$destination/usr/bin/fakesip"
chmod 0755 "$destination/usr/bin/fakesip"
EOF
chmod 0755 "$SDK/staging_dir/host/bin/apk"

FAKE_APK_BINARY="$TMP/fakesip.fixture" READELF="$TMP/bin/readelf" \
	sh "$COLLECTOR" "$SDK" "$TMP/output-one"

[ "$(find "$TMP/output-one" -maxdepth 1 -type f -name '*.apk' | wc -l)" -eq 1 ]
[ -f "$TMP/output-one/$(basename "$MAIN_APK")" ]
! find "$TMP/output-one" -maxdepth 1 -type f \( \
	-name 'kmod-*.apk' -o -name 'nftables-*.apk' -o -name 'coreutils-*.apk' \
	\) | grep -q .
[ -f "$TMP/output-one/THIRD_PARTY_SOURCES.md" ]
[ -f "$TMP/output-one/FakeHTTP-0.9.18.tar.gz" ]
[ -f "$TMP/output-one/FakeSIP-TaoistFuchen-0.9.4.tar.gz" ]
[ ! -e "$TMP/output-one/FakeSIP-Droid-MAX-0.9.3.tar.gz" ]
[ -f "$TMP/output-one/SHA256SUMS" ]

touch "$SDK/bin/packages/aarch64_cortex-a53/base/luci-app-taoistfuchen-2.1.0-r2-duplicate.apk"
if FAKE_APK_BINARY="$TMP/fakesip.fixture" READELF="$TMP/bin/readelf" \
	sh "$COLLECTOR" "$SDK" "$TMP/output-duplicate" >"$TMP/duplicate.log" 2>&1; then
	echo "artifact collector accepted multiple application APKs" >&2
	exit 1
fi
grep -Fq 'expected exactly one luci-app-taoistfuchen-*.apk' "$TMP/duplicate.log"

rm "$SDK/bin/packages/aarch64_cortex-a53/base/luci-app-taoistfuchen-2.1.0-r2-duplicate.apk"
python3 - "$TMP/fakesip-invalid.fixture" <<'PY'
import sys
from pathlib import Path

payload = bytearray(64)
payload[:6] = b"\x7fELF\x02\x01"
payload[18:20] = (183).to_bytes(2, "little")
payload.extend(b"/lib/ld-musl-aarch64.so.1\0")
Path(sys.argv[1]).write_bytes(payload)
PY
if FAKE_APK_BINARY="$TMP/fakesip-invalid.fixture" READELF="$TMP/bin/readelf" \
	sh "$COLLECTOR" "$SDK" "$TMP/output-invalid" >"$TMP/invalid.log" 2>&1; then
	echo "artifact collector accepted an invalid FakeSIP payload" >&2
	exit 1
fi
grep -Fq 'missing fakesip payload marker' "$TMP/invalid.log"

echo "build pipeline tests: ok"
