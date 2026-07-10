#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEFAULTS="$ROOT/luci-app-taoistfuchen/root/etc/uci-defaults/99_taoistfuchen"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

# Exercise the exact helper body installed on the router, without running the
# uci-defaults top-level actions against the host system.
eval "$(sed -n '/^legacy_remove_managed_file()/,/^}/p' "$DEFAULTS")"

mkdir -p "$TMP/restore" "$TMP/remove" "$TMP/preserve" "$TMP/retry"

printf 'custom\n' >"$TMP/restore/selected"
cp "$TMP/restore/selected" "$TMP/restore/logo.svg"
printf 'vendor\n' >"$TMP/restore/logo.svg.backup"
legacy_remove_managed_file "$TMP/restore/logo.svg" "$TMP/restore/selected"
grep -qx 'vendor' "$TMP/restore/logo.svg"
[ ! -e "$TMP/restore/logo.svg.backup" ]

printf 'custom\n' >"$TMP/remove/selected"
cp "$TMP/remove/selected" "$TMP/remove/logo.svg"
legacy_remove_managed_file "$TMP/remove/logo.svg" "$TMP/remove/selected"
[ ! -e "$TMP/remove/logo.svg" ]

printf 'custom\n' >"$TMP/preserve/selected"
printf 'new-vendor\n' >"$TMP/preserve/logo.svg"
printf 'old-vendor\n' >"$TMP/preserve/logo.svg.backup"
legacy_remove_managed_file "$TMP/preserve/logo.svg" "$TMP/preserve/selected"
grep -qx 'new-vendor' "$TMP/preserve/logo.svg"
[ ! -e "$TMP/preserve/logo.svg.backup" ]

printf 'custom\n' >"$TMP/retry/selected"
cp "$TMP/retry/selected" "$TMP/retry/logo.svg"
printf 'vendor\n' >"$TMP/retry/logo.svg.backup"
mktemp() { return 1; }
if legacy_remove_managed_file "$TMP/retry/logo.svg" "$TMP/retry/selected"; then
	echo "legacy restore unexpectedly succeeded" >&2
	exit 1
fi
grep -qx 'custom' "$TMP/retry/logo.svg"
grep -qx 'vendor' "$TMP/retry/logo.svg.backup"

# Old arbitrary same-origin SVG uploads must be reset to the trusted built-in
# asset instead of being copied into the 2.0 asset directory.
eval "$(sed -n '/^asset_file_allowed()/,/^}/p' "$DEFAULTS")"
LEGACY_ROOT="$TMP/legacy-root"
mkdir -p "$LEGACY_ROOT"
eval "$(sed -n '/^migrate_asset_option()/,/^}/p' "$DEFAULTS" |
	sed "s#/etc/taoistfuchen#$LEGACY_ROOT#g")"

ASSET_DIR="$TMP/assets"
DEFAULT_COPY="$ASSET_DIR/default-logo.svg"
mkdir -p "$ASSET_DIR"
printf '<svg/>\n' >"$LEGACY_ROOT/legacy.svg"
UCI_SOURCE="$LEGACY_ROOT/legacy.svg"
UCI_SET=''
uci() {
	[ "${1:-}" = '-q' ] && shift
	case "${1:-}" in
		get) printf '%s\n' "$UCI_SOURCE" ;;
		set) UCI_SET="${2:-}" ;;
		*) return 1 ;;
	esac
}
migrate_asset_option logo logo
[ "$UCI_SET" = "taoistfuchen.main.logo=$DEFAULT_COPY" ]
[ ! -e "$ASSET_DIR/legacy.svg" ]

UCI_SOURCE="$LEGACY_ROOT/../outside.png"
UCI_SET=''
migrate_asset_option logo logo
[ "$UCI_SET" = "taoistfuchen.main.logo=$DEFAULT_COPY" ]

printf '\211PNG\r\n\032\n\000\000\000\rIHDR\000\000\000\001\000\000\000\001' \
	>"$LEGACY_ROOT/brand.png"
UCI_SOURCE="$LEGACY_ROOT/brand.png"
UCI_SET=''
migrate_asset_option logo logo
[ "$UCI_SET" = "taoistfuchen.main.logo=$ASSET_DIR/brand.png" ]
cmp "$LEGACY_ROOT/brand.png" "$ASSET_DIR/brand.png"

echo "migration tests: ok"
