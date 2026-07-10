# OpenWrt 25.12.5 mediatek/mt7622 SDK package-default minimizer.
#
# The official SDK's Config-build.in defaults 1393 prebuilt packages to y/m.
# Turn unconditional package defaults off, then retain the exact kernel-module
# provider closure required to package kmod-nft-core and kmod-nft-queue. The
# SDK omits normal linux package metadata, so Kconfig cannot reconstruct this
# closure by itself. Re-audit this allowlist whenever the pinned SDK changes.

BEGIN {
	keep["PACKAGE_kmod-lib-crc32c"] = "y"
	keep["PACKAGE_kmod-nf-conntrack"] = "y"
	keep["PACKAGE_kmod-nf-conntrack6"] = "y"
	keep["PACKAGE_kmod-nf-log"] = "y"
	keep["PACKAGE_kmod-nf-log6"] = "y"
	keep["PACKAGE_kmod-nf-nat"] = "y"
	keep["PACKAGE_kmod-nf-reject"] = "y"
	keep["PACKAGE_kmod-nf-reject6"] = "y"
	keep["PACKAGE_kmod-nfnetlink"] = "y"
	keep["PACKAGE_kmod-nfnetlink-queue"] = "m"
	keep["PACKAGE_kmod-nft-core"] = "y"
	keep["PACKAGE_kmod-nft-queue"] = "m"
}

$1 == "config" {
	package_name = $2
	in_package = (package_name ~ /^PACKAGE_/)
}

in_package && $1 == "default" && NF == 2 && $2 ~ /^[nmy]$/ {
	value = (package_name in keep) ? keep[package_name] : "n"
	sub(/default[[:space:]]+[nmy]/, "default " value)
}

{ print }
