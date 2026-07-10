#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PKG="$ROOT/luci-app-taoistfuchen"
COMMON="$PKG/root/usr/share/taoistfuchen/service-common.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

sed -e 's#^PROG=.*#PROG="/bin/true"#' \
	-e "s#^COMMON=.*#COMMON=\"$COMMON\"#" \
	"$PKG/root/etc/init.d/fakehttp" >"$TMP/fakehttp"
sed -e 's#^PROG=.*#PROG="/bin/true"#' \
	-e "s#^COMMON=.*#COMMON=\"$COMMON\"#" \
	"$PKG/root/etc/init.d/fakesip" >"$TMP/fakesip"

config_load() { :; }

config_get() {
	local destination="$1" section="$2" option="$3" default="${4-}" marker resolved
	eval "marker=\${CFG_${section}_${option}+set}"
	if [ "$marker" = set ]; then
		eval "resolved=\${CFG_${section}_${option}}"
	else
		resolved="$default"
	fi
	eval "$destination=\$resolved"
}

config_get_bool() {
	local destination="$1" value
	config_get value "$2" "$3" "${4-0}"
	case "$value" in 1|on|true|yes|enabled) value=1 ;; *) value=0 ;; esac
	eval "$destination=\$value"
}

config_list_foreach() {
	local section="$1" option="$2" callback="$3" values value
	eval "values=\${CFG_${section}_${option}-}"
	for value in $values; do "$callback" "$value"; done
}

config_foreach() {
	local callback="$1" type="$2" section
	[ "$type" = payload ] || return 0
	for section in $PAYLOAD_SECTIONS; do "$callback" "$section"; done
}

logger() { :; }

COMMAND_ARGS=''
NETDEVS=''
append_line() {
	local variable="$1" value="$2" current
	eval "current=\${$variable}"
	if [ -n "$current" ]; then current="$current
$value"; else current="$value"; fi
	eval "$variable=\$current"
}
procd_open_instance() { :; }
procd_close_instance() { :; }
procd_set_param() {
	local parameter="$1" value
	shift
	[ "$parameter" = command ] || return 0
	for value in "$@"; do append_line COMMAND_ARGS "$value"; done
}
procd_append_param() {
	local parameter="$1" value
	shift
	case "$parameter" in
		command) for value in "$@"; do append_line COMMAND_ARGS "$value"; done ;;
		netdev) for value in "$@"; do append_line NETDEVS "$value"; done ;;
	esac
}

SIBLING_HTTP_ENABLED=0
SIBLING_HTTP_QUEUE=8970
SIBLING_SIP_ENABLED=0
SIBLING_SIP_QUEUE=8971
uci() {
	[ "${1-}" = -q ] && shift
	[ "${1-}" = get ] && shift
	case "${1-}" in
		fakehttp.main.enabled) printf '%s\n' "$SIBLING_HTTP_ENABLED" ;;
		fakehttp.main.queue_num) printf '%s\n' "$SIBLING_HTTP_QUEUE" ;;
		fakesip.main.enabled) printf '%s\n' "$SIBLING_SIP_ENABLED" ;;
		fakesip.main.queue_num) printf '%s\n' "$SIBLING_SIP_QUEUE" ;;
		*) return 1 ;;
	esac
}

# shellcheck source=/dev/null
. "$TMP/fakehttp"
tf_interface_exists() { tf_valid_interface "$1" && [ "$1" = wan0 ]; }
tf_cleanup_nft_table() { :; }

CFG_main_enabled=1
CFG_main_interface_mode=selected
CFG_main_interface='wan0 wan0'
CFG_main_direction=outbound
CFG_main_family=dual
CFG_main_repeat=2
CFG_main_ttl=3
CFG_main_hop_estimation=1
CFG_main_dynamic_ttl_pct=0
CFG_main_log_connections=0
CFG_main_queue_num=8970
CFG_main_fwmark=0x8000
CFG_main_fwmask=0x8000
PAYLOAD_SECTIONS='p1 p2 p3'
CFG_p1_enabled=1
CFG_p1_type=http
CFG_p1_host=a.example
CFG_p2_enabled=1
CFG_p2_type=https
CFG_p2_host=b.example
CFG_p3_enabled=1
CFG_p3_type=http
CFG_p3_host=c.example

start_service

EXPECTED_HTTP='/bin/true
-i
wan0
-1
-4
-6
-h
c.example
-e
b.example
-h
a.example
-r
2
-t
3
-n
8970
-m
0x8000
-x
0x8000
-s'
[ "$COMMAND_ARGS" = "$EXPECTED_HTTP" ] || {
	echo "unexpected FakeHTTP command arguments:" >&2
	printf '%s\n' "$COMMAND_ARGS" >&2
	exit 1
}
[ "$NETDEVS" = wan0 ]

COMMAND_ARGS=''
SIBLING_SIP_ENABLED=1
SIBLING_SIP_QUEUE=8970
if start_service; then
	echo "FakeHTTP accepted a conflicting FakeSIP queue" >&2
	exit 1
fi
[ -z "$COMMAND_ARGS" ]
SIBLING_SIP_ENABLED=0
SIBLING_SIP_QUEUE=8971

# shellcheck source=/dev/null
. "$TMP/fakesip"
tf_interface_exists() { tf_valid_interface "$1" && [ "$1" = wan0 ]; }
tf_cleanup_nft_table() { :; }

COMMAND_ARGS=''
NETDEVS=''
CFG_main_enabled=1
CFG_main_interface_mode=selected
CFG_main_interface='wan0 wan0'
CFG_main_direction=both
CFG_main_family=ipv4
CFG_main_port_mode=exclude
CFG_main_ports=53
CFG_main_payload_mode=auto
CFG_main_sip_uri=''
CFG_main_repeat=2
CFG_main_ttl=3
CFG_main_hop_estimation=1
CFG_main_dynamic_ttl_pct=0
CFG_main_log_connections=0
CFG_main_queue_num=8971
CFG_main_fwmark=0x10000
CFG_main_fwmask=0x10000

start_service

EXPECTED_SIP='/bin/true
-i
wan0
-0
-1
-4
-P
53
-r
2
-t
3
-n
8971
-m
0x10000
-x
0x10000
-s'
[ "$COMMAND_ARGS" = "$EXPECTED_SIP" ] || {
	echo "unexpected FakeSIP command arguments:" >&2
	printf '%s\n' "$COMMAND_ARGS" >&2
	exit 1
}
[ "$NETDEVS" = wan0 ]

COMMAND_ARGS=''
NETDEVS=''
CFG_main_direction=outbound
start_service
printf '%s\n' "$COMMAND_ARGS" | grep -Fx -- '-0' >/dev/null
if printf '%s\n' "$COMMAND_ARGS" | grep -Fx -- '-1' >/dev/null; then
	echo "FakeSIP outbound mode was not compensated for the upstream flag inversion" >&2
	exit 1
fi
CFG_main_direction=both

COMMAND_ARGS=''
SIBLING_HTTP_ENABLED=1
SIBLING_HTTP_QUEUE=8971
if start_service; then
	echo "FakeSIP accepted a conflicting FakeHTTP queue" >&2
	exit 1
fi
[ -z "$COMMAND_ARGS" ]

echo "service command tests: ok"
