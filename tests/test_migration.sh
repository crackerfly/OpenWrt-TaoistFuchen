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

# 2.1-r2 uses outbound dual-stack defaults without changing any existing valid
# selection. Missing or invalid values fall back to the new defaults.
eval "$(sed -n '/^normalize_fakesip_direction()/,/^}/p' "$DEFAULTS")"
eval "$(sed -n '/^normalize_fakesip_family()/,/^}/p' "$DEFAULTS")"
UCI_DIRECTION=''
UCI_DIRECTION_PRESENT=0
UCI_FAMILY=''
UCI_FAMILY_PRESENT=0
UCI_SET=''
logger() { :; }
uci() {
	[ "${1:-}" = '-q' ] && shift
	case "${1:-}" in
		get)
			case "${2:-}" in
				fakesip.main.direction)
					[ "$UCI_DIRECTION_PRESENT" = 1 ] || return 1
					printf '%s\n' "$UCI_DIRECTION"
					;;
				fakesip.main.family)
					[ "$UCI_FAMILY_PRESENT" = 1 ] || return 1
					printf '%s\n' "$UCI_FAMILY"
					;;
				*) return 1 ;;
			esac
			;;
		set) UCI_SET="${2:-}" ;;
		*) return 1 ;;
	esac
}

normalize_fakesip_direction
[ "$UCI_SET" = 'fakesip.main.direction=outbound' ]

for direction in inbound outbound both; do
	UCI_DIRECTION_PRESENT=1
	UCI_DIRECTION="$direction"
	UCI_SET=''
	normalize_fakesip_direction
	[ -z "$UCI_SET" ]
done

UCI_DIRECTION_PRESENT=1
UCI_DIRECTION='unexpected'
UCI_SET=''
normalize_fakesip_direction
[ "$UCI_SET" = 'fakesip.main.direction=outbound' ]

UCI_SET=''
normalize_fakesip_family
[ "$UCI_SET" = 'fakesip.main.family=dual' ]

for family in ipv4 ipv6 dual; do
	UCI_FAMILY_PRESENT=1
	UCI_FAMILY="$family"
	UCI_SET=''
	normalize_fakesip_family
	[ -z "$UCI_SET" ]
done

UCI_FAMILY_PRESENT=1
UCI_FAMILY='unexpected'
UCI_SET=''
normalize_fakesip_family
[ "$UCI_SET" = 'fakesip.main.family=dual' ]

# r3 intentionally resets both boot delays once. Its completion marker makes a
# reinstall idempotent and must be written only after both package commits.
eval "$(sed -n '/^migrate_r3_boot_delays()/,/^}/p' "$DEFAULTS")"

reset_boot_delay_case() {
	UCI_MARKER="$1"
	UCI_FAKESIP_DELAY="$2"
	UCI_FAKEHTTP_DELAY="$3"
	UCI_FAIL_COMMIT="${4:-}"
	UCI_BOOT_WRITES=''
}

uci() {
	[ "${1:-}" = '-q' ] && shift
	case "${1:-}" in
		get)
			case "${2:-}" in
				taoistfuchen.main.boot_delay_migrated_r3)
					[ "$UCI_MARKER" != '__missing__' ] || return 1
					printf '%s\n' "$UCI_MARKER"
					;;
				*) return 1 ;;
			esac
			;;
		set)
			UCI_BOOT_WRITES="${UCI_BOOT_WRITES}${UCI_BOOT_WRITES:+
}${2:-}"
			case "${2:-}" in
				fakesip.main.boot_delay=*) UCI_FAKESIP_DELAY="${2#*=}" ;;
				fakehttp.main.boot_delay=*) UCI_FAKEHTTP_DELAY="${2#*=}" ;;
				taoistfuchen.main.boot_delay_migrated_r3=*) UCI_MARKER="${2#*=}" ;;
				*) return 1 ;;
			esac
			;;
		commit)
			[ "${2:-}" != "$UCI_FAIL_COMMIT" ]
			;;
		*) return 1 ;;
	esac
}

reset_boot_delay_case __missing__ 17 599
migrate_r3_boot_delays
[ "$UCI_FAKESIP_DELAY" = 40 ]
[ "$UCI_FAKEHTTP_DELAY" = 60 ]
[ "$UCI_MARKER" = 1 ]

reset_boot_delay_case 1 7 8
migrate_r3_boot_delays
[ "$UCI_FAKESIP_DELAY" = 7 ]
[ "$UCI_FAKEHTTP_DELAY" = 8 ]
[ -z "$UCI_BOOT_WRITES" ]

reset_boot_delay_case invalid 17 599
migrate_r3_boot_delays
[ "$UCI_FAKESIP_DELAY" = 40 ]
[ "$UCI_FAKEHTTP_DELAY" = 60 ]
[ "$UCI_MARKER" = 1 ]

reset_boot_delay_case __missing__ 17 599 fakesip
if migrate_r3_boot_delays; then
	echo "r3 migration ignored a fakesip commit failure" >&2
	exit 1
fi
[ "$UCI_MARKER" = __missing__ ]

reset_boot_delay_case __missing__ 17 599 fakehttp
if migrate_r3_boot_delays; then
	echo "r3 migration ignored a fakehttp commit failure" >&2
	exit 1
fi
[ "$UCI_MARKER" = __missing__ ]

echo "migration tests: ok"
