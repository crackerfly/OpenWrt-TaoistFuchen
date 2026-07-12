#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PKG="$ROOT/luci-app-taoistfuchen"
HOTPLUG="$PKG/root/etc/hotplug.d/iface/99-taoistfuchen"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

INIT_DIR="$TMP/init.d"
INIT_LOG="$TMP/init.log"
LOGGER_LOG="$TMP/logger.log"
NETWORK_HELPERS="$TMP/network.sh"
TF_SYS_CLASS_NET="$TMP/sys/class/net"
TF_BOOT_STATE_DIR="$TMP/boot-state"
mkdir -p "$INIT_DIR" "$TF_SYS_CLASS_NET/wan0" "$TF_SYS_CLASS_NET/other0"
: >"$INIT_LOG"
: >"$LOGGER_LOG"

for service in fakehttp fakesip; do
	printf '%s\n' \
		'#!/bin/sh' \
		'printf "%s %s %s\n" "${0##*/}" "${1:-}" "${2:-}" >>"$TF_HOTPLUG_INIT_LOG"' \
		>"$INIT_DIR/$service"
	chmod 0755 "$INIT_DIR/$service"
done

printf '%s\n' \
	'network_flush_cache() { :; }' \
	'network_get_device() {' \
	'  [ "${2:-}" = "${TF_NETWORK_INTERFACE:-wan}" ] || return 1' \
	'  [ -n "${TF_NETWORK_DEVICE:-}" ] || return 1' \
	'  eval "$1=\$TF_NETWORK_DEVICE"' \
	'}' >"$NETWORK_HELPERS"

TF_COMMON="$PKG/root/usr/share/taoistfuchen/service-common.sh"
TF_NETWORK_HELPERS="$NETWORK_HELPERS"
TF_INIT_DIR="$INIT_DIR"
TF_HOTPLUG_INIT_LOG="$INIT_LOG"
TF_NETWORK_INTERFACE=wan
TF_NETWORK_DEVICE=wan0
export TF_COMMON TF_NETWORK_HELPERS TF_INIT_DIR TF_HOTPLUG_INIT_LOG
export TF_SYS_CLASS_NET TF_BOOT_STATE_DIR TF_NETWORK_INTERFACE TF_NETWORK_DEVICE

HTTP_ENABLED=1
SIP_ENABLED=1
HTTP_MODE=selected
HTTP_INTERFACES=wan0
SIP_INTERFACES=wan0

uci() {
	[ "${1:-}" = -q ] && shift
	[ "${1:-}" = get ] && shift
	case "${1:-}" in
		fakehttp.main.enabled) printf '%s\n' "$HTTP_ENABLED" ;;
		fakesip.main.enabled) printf '%s\n' "$SIP_ENABLED" ;;
		fakehttp.main.interface_mode) printf '%s\n' "$HTTP_MODE" ;;
		fakesip.main.interface_mode) printf 'selected\n' ;;
		fakehttp.main.interface) printf '%s\n' "$HTTP_INTERFACES" ;;
		fakesip.main.interface) printf '%s\n' "$SIP_INTERFACES" ;;
		*) return 1 ;;
	esac
}

logger() { printf '%s\n' "$*" >>"$LOGGER_LOG"; }

run_hotplug() {
	# Hotplug files are sourced by netifd; source inside a function so their
	# defensive return paths can be exercised without terminating this test.
	# shellcheck source=/dev/null
	. "$HOTPLUG"
}

reset_logs() {
	: >"$INIT_LOG"
	: >"$LOGGER_LOG"
}

ACTION=ifdown
DEVICE=wan0
INTERFACE=wan
run_hotplug
[ "$(cat "$INIT_LOG")" = 'fakehttp link_down wan0
fakesip link_down wan0' ]

reset_logs
ACTION=ifup
DEVICE=wan0
run_hotplug
[ "$(cat "$INIT_LOG")" = 'fakehttp link_up wan0
fakesip link_up wan0' ]

# Real netifd down events omit DEVICE. The preceding ifup must have cached the
# validated L3 mapping so a later down with no live ubus l3_device still stops
# exactly pppoe-wan/wan0 instead of guessing the physical parent.
reset_logs
ACTION=ifdown
DEVICE=''
TF_NETWORK_DEVICE=''
export TF_NETWORK_DEVICE
run_hotplug
[ "$(cat "$INIT_LOG")" = 'fakehttp link_down wan0
fakesip link_down wan0' ]

reset_logs
ACTION=ifup
DEVICE=other0
run_hotplug
[ ! -s "$INIT_LOG" ]

# DEVICE may be absent when netifd still exposes a unique L3 device through
# INTERFACE. Resolve it rather than guessing or dropping a valid event.
reset_logs
DEVICE=''
TF_NETWORK_DEVICE=wan0
export TF_NETWORK_DEVICE
run_hotplug
[ "$(cat "$INIT_LOG")" = 'fakehttp link_up wan0
fakesip link_up wan0' ]

reset_logs
DEVICE=''
TF_NETWORK_DEVICE=''
INTERFACE=uncached
export TF_NETWORK_DEVICE
run_hotplug
[ ! -s "$INIT_LOG" ]
[ -s "$LOGGER_LOG" ]

reset_logs
HTTP_ENABLED=0
SIP_ENABLED=0
DEVICE=wan0
INTERFACE=wan
run_hotplug
[ ! -s "$INIT_LOG" ]

reset_logs
HTTP_ENABLED=1
SIP_ENABLED=1
HTTP_MODE=all
DEVICE=other0
run_hotplug
[ "$(cat "$INIT_LOG")" = 'fakehttp link_up other0' ]

reset_logs
HTTP_MODE=selected
DEVICE=ghost0
run_hotplug
[ ! -s "$INIT_LOG" ]
[ -s "$LOGGER_LOG" ]

reset_logs
DEVICE='wan0;reboot'
run_hotplug
[ ! -s "$INIT_LOG" ]
[ -s "$LOGGER_LOG" ]

echo "hotplug tests: ok"
