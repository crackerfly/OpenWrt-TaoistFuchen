#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
	echo "usage: $0 OPENWRT_SDK_DIR OUTPUT_DIR" >&2
	exit 2
fi

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SDK_DIR="$(CDPATH= cd -- "$1" && pwd)"
OUTPUT_DIR="$2"
PACKAGE_NAME="luci-app-taoistfuchen"

if [ -e "$OUTPUT_DIR" ]; then
	echo "artifact output already exists: $OUTPUT_DIR" >&2
	exit 1
fi

LIST="$(mktemp)"
trap 'rm -f "$LIST"' EXIT INT TERM
find "$SDK_DIR/bin" -type f -name "${PACKAGE_NAME}-*.apk" -print > "$LIST"

COUNT="$(wc -l < "$LIST" | tr -d ' ')"
if [ "$COUNT" -ne 1 ]; then
	echo "expected exactly one ${PACKAGE_NAME}-*.apk, found $COUNT" >&2
	exit 1
fi

PACKAGE_APK="$(sed -n '1p' "$LIST")"
python3 "$ROOT/scripts/verify-built-apk.py" \
	"$SDK_DIR/staging_dir/host/bin/apk" "$PACKAGE_APK"

mkdir -p "$OUTPUT_DIR"
cp "$PACKAGE_APK" "$OUTPUT_DIR/"
cp "$ROOT/THIRD_PARTY_SOURCES.md" \
	"$ROOT/luci-app-taoistfuchen/COPYING" \
	"$ROOT/luci-app-taoistfuchen/LICENSE" \
	"$OUTPUT_DIR/"
for archive in \
	FakeHTTP-0.9.18.tar.gz \
	FakeSIP-TaoistFuchen-0.9.5.tar.gz; do
	[ -f "$ROOT/third_party/sources/$archive" ] || {
		echo "missing corresponding source archive: $archive" >&2
		exit 1
	}
	cp "$ROOT/third_party/sources/$archive" "$OUTPUT_DIR/"
done

OUTPUT_APK_COUNT="$(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d ' ')"
[ "$OUTPUT_APK_COUNT" -eq 1 ] || {
	echo "artifact contains $OUTPUT_APK_COUNT APK files; expected one" >&2
	exit 1
}

if find "$OUTPUT_DIR" -maxdepth 1 -type f \( \
	-name 'kmod-*.apk' -o \
	-name 'nftables-*.apk' -o \
	-name 'coreutils-*.apk' -o \
	-name '*.ipk' \
	\) | grep -q .; then
	echo "dependency package found in artifact" >&2
	exit 1
fi

(
	cd "$OUTPUT_DIR"
	sha256sum COPYING LICENSE THIRD_PARTY_SOURCES.md \
		*.tar.gz "$(basename "$PACKAGE_APK")" > SHA256SUMS
)

echo "artifact prepared with one installable APK:"
find "$OUTPUT_DIR" -maxdepth 1 -type f -print | sort
