#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: $0 OPENWRT_SDK_DIR" >&2
	exit 2
fi

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SDK_DIR="$(CDPATH= cd -- "$1" && pwd)"
CONFIG_BUILD="$SDK_DIR/Config-build.in"

if [ ! -f "$CONFIG_BUILD" ] || [ ! -f "$SDK_DIR/Makefile" ]; then
	echo "not an OpenWrt SDK directory: $SDK_DIR" >&2
	exit 1
fi

TMP_CONFIG="$(mktemp "$SDK_DIR/Config-build.in.XXXXXX")"
trap 'rm -f "$TMP_CONFIG"' EXIT INT TERM
awk -f "$ROOT/scripts/minimize-sdk-config.awk" "$CONFIG_BUILD" > "$TMP_CONFIG"
mv "$TMP_CONFIG" "$CONFIG_BUILD"
trap - EXIT INT TERM

cat > "$SDK_DIR/.config" <<'EOF'
# CONFIG_ALL is not set
# CONFIG_ALL_KMODS is not set
# CONFIG_ALL_NONSHARED is not set
CONFIG_PACKAGE_luci-app-taoistfuchen=m
EOF

(
	cd "$SDK_DIR"
	make defconfig

	for symbol in ALL ALL_KMODS ALL_NONSHARED; do
		grep -Fqx "# CONFIG_${symbol} is not set" .config
	done
	grep -Fqx 'CONFIG_PACKAGE_luci-app-taoistfuchen=m' .config

	module_count="$(grep -Ec '^CONFIG_PACKAGE_.*=m$' .config || true)"
	kmod_module_count="$(grep -Ec '^CONFIG_PACKAGE_kmod-.*=m$' .config || true)"
	kmod_builtin_count="$(grep -Ec '^CONFIG_PACKAGE_kmod-.*=y$' .config || true)"

	[ "$module_count" -eq 9 ] || {
		echo "unexpected SDK module package count: $module_count (expected 9)" >&2
		exit 1
	}
	[ "$kmod_module_count" -eq 2 ] || {
		echo "unexpected modular kmod count: $kmod_module_count (expected 2)" >&2
		exit 1
	}
	[ "$kmod_builtin_count" -eq 10 ] || {
		echo "unexpected built-in kmod count: $kmod_builtin_count (expected 10)" >&2
		exit 1
	}

	for expected in \
		kmod-lib-crc32c=y \
		kmod-nf-conntrack=y \
		kmod-nf-conntrack6=y \
		kmod-nf-log=y \
		kmod-nf-log6=y \
		kmod-nf-nat=y \
		kmod-nf-reject=y \
		kmod-nf-reject6=y \
		kmod-nfnetlink=y \
		kmod-nfnetlink-queue=m \
		kmod-nft-core=y \
		kmod-nft-queue=m \
		libmnl=y \
		libnetfilter-queue=m \
		libnfnetlink=m; do
		grep -Fqx "CONFIG_PACKAGE_${expected}" .config
	done

	if grep -Eq '^CONFIG_PACKAGE_.*firmware.*=[my]$' .config; then
		echo "unexpected firmware package selected by SDK configuration" >&2
		exit 1
	fi

	echo "minimal SDK configuration verified: m=$module_count, kmod-m=$kmod_module_count, kmod-y=$kmod_builtin_count"
)
