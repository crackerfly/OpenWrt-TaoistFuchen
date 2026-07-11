#!/bin/sh

# Shared validation and cleanup helpers for the FakeHTTP and FakeSIP
# procd services. Keep this file compatible with BusyBox ash.

tf_valid_interface() {
	local value="$1"

	[ -n "$value" ] && [ "${#value}" -le 15 ] || return 1
	[ "$value" != 'lo' ] || return 1
	case "$value" in
		*[!A-Za-z0-9_.-]*) return 1 ;;
	esac
	return 0
}

tf_interface_exists() {
	tf_valid_interface "$1" || return 1
	[ -e "/sys/class/net/$1" ] || [ -L "/sys/class/net/$1" ]
}

tf_valid_hostname() {
	local hostname="$1" old_ifs label

	[ -n "$hostname" ] && [ "${#hostname}" -le 253 ] || return 1
	case "$hostname" in
		.*|*.|*..*|*[!A-Za-z0-9.-]*) return 1 ;;
	esac

	old_ifs="$IFS"
	IFS='.'
	set -- $hostname
	IFS="$old_ifs"

	for label in "$@"; do
		[ -n "$label" ] && [ "${#label}" -le 63 ] || return 1
		case "$label" in
			-*|*-) return 1 ;;
		esac
	done
	return 0
}

tf_valid_uint_range() {
	local value="$1" minimum="$2" maximum="$3" normalized

	case "$value" in
		''|*[!0-9]*|0?*) return 1 ;;
	esac

	# Avoid implementation-defined overflow in the shell arithmetic parser.
	[ "${#value}" -le 10 ] || return 1
	normalized="$value"
	while [ "${#normalized}" -gt 1 ] && [ "${normalized#0}" != "$normalized" ]; do
		normalized="${normalized#0}"
	done

	[ "$normalized" -ge "$minimum" ] 2>/dev/null || return 1
	[ "$normalized" -le "$maximum" ] 2>/dev/null || return 1
	return 0
}

tf_valid_port_spec() {
	local spec="$1" old_ifs item first last

	[ -n "$spec" ] || return 1
	case "$spec" in
		*[!0-9,-]*|,*|*,|*,,*) return 1 ;;
	esac

	old_ifs="$IFS"
	IFS=','
	set -- $spec
	IFS="$old_ifs"

	for item in "$@"; do
		case "$item" in
			*-*)
				first="${item%%-*}"
				last="${item#*-}"
				[ "$last" = "${last#*-}" ] || return 1
				tf_valid_uint_range "$first" 1 65535 || return 1
				tf_valid_uint_range "$last" 1 65535 || return 1
				[ "$first" -le "$last" ] 2>/dev/null || return 1
				;;
			*)
				tf_valid_uint_range "$item" 1 65535 || return 1
				;;
		esac
	done
	return 0
}

tf_valid_u32() {
	local value="$1" digits normalized numeric

	case "$value" in
		0[xX]*)
			digits="${value#??}"
			[ -n "$digits" ] && [ "${#digits}" -le 8 ] || return 1
			case "$digits" in *[!0-9A-Fa-f]*) return 1 ;; esac
			numeric=$((value))
			;;
		*)
			case "$value" in ''|*[!0-9]*|0?*) return 1 ;; esac
			[ "${#value}" -le 10 ] || return 1
			normalized="$value"
			while [ "${#normalized}" -gt 1 ] && [ "${normalized#0}" != "$normalized" ]; do
				normalized="${normalized#0}"
			done
			[ "$normalized" -le 4294967295 ] 2>/dev/null || return 1
			numeric="$normalized"
			;;
	esac

	[ "$numeric" -gt 0 ] 2>/dev/null && [ "$numeric" -le 4294967295 ] 2>/dev/null
}

tf_mark_fits_mask() {
	local mark="$1" mask="$2" mark_num mask_num

	tf_valid_u32 "$mark" || return 1
	tf_valid_u32 "$mask" || return 1
	mark_num=$((mark))
	mask_num=$((mask))
	[ $((mark_num & mask_num)) -eq "$mark_num" ]
}

tf_valid_sip_uri() {
	local uri="$1" body user authority host port

	[ -n "$uri" ] && [ "${#uri}" -le 255 ] || return 1
	case "$uri" in
		sip:*) ;;
		*) return 1 ;;
	esac
	case "$uri" in
		*[!A-Za-z0-9_.!~*+\&=%@:-]*) return 1 ;;
	esac

	body="${uri#sip:}"
	user="${body%%@*}"
	authority="${body#*@}"
	[ "$body" != "$authority" ] && [ -n "$user" ] && [ -n "$authority" ] || return 1
	[ "$authority" = "${authority#*@}" ] || return 1

	case "$user" in *[!A-Za-z0-9_.!~*+\&=%-]*) return 1 ;; esac
	case "$authority" in
		*:*)
			host="${authority%%:*}"
			port="${authority#*:}"
			[ "$port" = "${port#*:}" ] || return 1
			tf_valid_uint_range "$port" 1 65535 || return 1
			;;
		*) host="$authority" ;;
	esac

	tf_valid_hostname "$host"
}

tf_valid_fakehttp_payload_location() {
	local path="$1" name

	case "$path" in
		/etc/taoistfuchen/fakehttp-payloads/*.bin) ;;
		*) return 1 ;;
	esac
	name="${path##*/}"
	[ "$path" = "/etc/taoistfuchen/fakehttp-payloads/$name" ] || return 1
	[ -n "$name" ] && [ "${#name}" -le 96 ] || return 1
	case "$name" in .*|*[!A-Za-z0-9._-]*) return 1 ;; esac
	case "$name" in [A-Za-z0-9]*.bin) ;; *) return 1 ;; esac
	return 0
}

tf_valid_fakehttp_payload_path() {
	local path="$1" size

	tf_valid_fakehttp_payload_location "$path" || return 1
	[ -f "$path" ] && [ ! -L "$path" ] || return 1
	size="$(wc -c < "$path" 2>/dev/null)" || return 1
	tf_valid_uint_range "$size" 1 1200
}

tf_cleanup_nft_table() {
	local table="$1"

	case "$table" in
		fakehttp|fakesip) ;;
		*) return 1 ;;
	esac
	command -v nft >/dev/null 2>&1 || return 0
	nft delete table ip "$table" >/dev/null 2>&1 || true
	nft delete table ip6 "$table" >/dev/null 2>&1 || true
}
