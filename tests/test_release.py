#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import stat
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PKG = ROOT / "luci-app-taoistfuchen"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    makefile = text(PKG / "Makefile")
    assert "PKG_VERSION:=2.0.0" in makefile
    assert "PKG_RELEASE:=2" in makefile
    assert "LUCI_PKGARCH:=aarch64_cortex-a53" in makefile
    assert (
        "LUCI_DEPENDS:=+luci-base +cgi-io +nftables +kmod-nft-queue "
        "+coreutils-stat +coreutils-od"
    ) in makefile
    assert "+kmod-nft-core" not in makefile
    assert "LUCI_MAINTAINER:=Hevil" in makefile
    assert "LUCI_URL:=https://github.com/crackerfly/OpenWrt-TaoistFuchen" in makefile
    assert "PKG_MAINTAINER" not in makefile
    assert "GPL-3.0" in makefile and "MIT" in makefile
    for config in ("taoistfuchen", "fakehttp", "fakesip"):
        assert f"/etc/config/{config}" in makefile

    fakehttp_cfg = text(PKG / "root/etc/config/fakehttp")
    for needle in (
        "option direction 'outbound'",
        "option family 'dual'",
        "option queue_num '8970'",
        "config payload",
        "option type 'http'",
    ):
        assert needle in fakehttp_cfg, needle
    assert "list interface ''" not in fakehttp_cfg

    fakesip_cfg = text(PKG / "root/etc/config/fakesip")
    for needle in (
        "option direction 'both'",
        "option family 'ipv4'",
        "option port_mode 'exclude'",
        "option ports '53'",
        "option queue_num '8971'",
    ):
        assert needle in fakesip_cfg, needle
    assert "list interface ''" not in fakesip_cfg

    fakehttp_init = text(PKG / "root/etc/init.d/fakehttp")
    fakesip_init = text(PKG / "root/etc/init.d/fakesip")
    for init in (fakehttp_init, fakesip_init):
        assert "boot()" not in init
        assert "sleep " not in init
        assert "procd_add_reload_trigger" in init
        assert "service_stopped()" in init
        assert "-w" not in init
    assert "-1" in fakehttp_init
    assert "-0" in fakesip_init and "-1" in fakesip_init and "-4" in fakesip_init
    assert "-P" in fakesip_init and "0x10000" in fakesip_init

    assert not (PKG / "root/usr/share/taoistfuchen/logclean.sh").exists()
    defaults = text(PKG / "root/etc/uci-defaults/99_taoistfuchen")
    # Upgrade cleanup may remove the vulnerable 1.x cron entry, but no new
    # scheduled task or file logger may be installed.
    assert "logclean.sh" not in defaults
    assert ">> /etc/crontabs" not in defaults
    assert "cleanup_legacy_theme_mutations" in defaults
    assert "TAOIST_FUCHEN_START" in defaults
    assert "migrate_asset_option logo logo" in defaults
    assert "migrate_asset_option favicon favicon" in defaults
    assert "/var/run/taoistfuchen-upload" in defaults
    assert "sleep " not in text(PKG / "root/etc/hotplug.d/iface/99-taoistfuchen")

    for executable in (
        PKG / "root/usr/bin/fakehttp",
        PKG / "root/usr/bin/fakesip",
        PKG / "root/etc/init.d/taoistfuchen",
        PKG / "root/etc/init.d/fakehttp",
        PKG / "root/etc/init.d/fakesip",
        PKG / "root/etc/uci-defaults/99_taoistfuchen",
        PKG / "root/www/cgi-bin/taoistfuchen-upload",
    ):
        assert executable.stat().st_mode & stat.S_IXUSR, f"not executable: {executable}"

    default_svg = PKG / "root/usr/share/taoistfuchen/assets/default-logo.svg"
    assert default_svg.is_file()
    svg = text(default_svg).lower()
    for forbidden in ("<script", "<foreignobject", "javascript:", "@import", "url("):
        assert forbidden not in svg
    root = ET.parse(default_svg).getroot()
    for element in root.iter():
        assert not element.tag.lower().endswith(("script", "foreignobject"))
        for name, value in element.attrib.items():
            lname, lvalue = name.lower(), value.strip().lower()
            assert not lname.startswith("on")
            if lname.endswith("href"):
                assert not lvalue.startswith(("http://", "https://", "//"))

    logo_init = text(PKG / "root/etc/init.d/taoistfuchen")
    assert "TAOISTFUCHEN_CUSTOMLOGO_START" in logo_init
    assert "luci/template/themes/bootstrap/header.ut" in logo_init
    assert "themes/argon/header.htm" in logo_init
    assert "themes/fluent/header.ut" in logo_init
    assert ".backup" not in logo_init
    runtime_js = PKG / "root/www/luci-static/taoistfuchen/customlogo-runtime.js"
    assert runtime_js.is_file()

    acl_path = PKG / "root/usr/share/rpcd/acl.d/luci-app-taoistfuchen.json"
    acl = json.loads(text(acl_path))
    for name in (
        "luci-app-taoistfuchen-logo",
        "luci-app-taoistfuchen-fakehttp",
        "luci-app-taoistfuchen-fakesip",
    ):
        assert name in acl
    acl_text = text(acl_path)
    assert '"/etc/taoistfuchen/assets/*": [ "read", "write"' not in acl_text
    assert '"log": [ "read" ]' not in acl_text
    assert '"/sbin/logread -e fakehttp": [ "exec" ]' in acl_text
    assert '"/sbin/logread -e fakesip": [ "exec" ]' in acl_text
    for name in ("luci-app-taoistfuchen-fakehttp", "luci-app-taoistfuchen-fakesip"):
        assert acl[name]["read"]["cgi-io"] == ["exec"]

    menu = json.loads(text(PKG / "root/usr/share/luci/menu.d/luci-app-taoistfuchen.json"))
    assert "depends" not in menu["admin/services/taoistfuchen"]

    sources = text(ROOT / "THIRD_PARTY_SOURCES.md")
    assert "FakeHTTP 0.9.18" in sources
    assert "Droid-MAX/FakeSIP 0.9.3" in sources
    assert "2a48dc7c1d61a582" in sources
    assert "3f49b5ef397dc0b5" in sources
    assert (ROOT / "third_party/sources/FakeHTTP-0.9.18.tar.gz").is_file()
    assert (ROOT / "third_party/sources/FakeSIP-Droid-MAX-0.9.3.tar.gz").is_file()

    readme = text(ROOT / "README.md")
    for needle in ("FakeHTTP 0.9.18", "FakeSIP 0.9.3"):
        assert needle in readme
    assert "2.4.3" in readme and "argon" in readme.lower()
    assert "luci-theme-fluent" in readme.lower()
    for needle in (
        ".github/workflows/build.yml",
        "apk add --allow-untrusted /tmp/luci-app-taoistfuchen-*.apk",
        "自动下载",
        "仓库根目录",
    ):
        assert needle in readme, needle

    web_upload = text(ROOT / "GITHUB_WEB_UPLOAD.md")
    for needle in (
        ".github/workflows/build.yml",
        "luci-app-taoistfuchen/",
        "README.md",
        "仓库根目录",
    ):
        assert needle in web_upload, needle

    workflow = text(ROOT / ".github/workflows/build.yml")
    normalize = "sh ./scripts/normalize-source-permissions.sh"
    regression = "sudo -E ./tests/run.sh"
    copy_to_sdk = "cp -a luci-app-taoistfuchen openwrt-sdk/package/"
    assert normalize in workflow
    assert workflow.index(normalize) < workflow.index(regression)
    assert workflow.index(normalize) < workflow.index(copy_to_sdk)
    assert "../scripts/configure-openwrt-sdk.sh ." in workflow
    assert "sh scripts/prepare-artifact.sh openwrt-sdk output_pkg" in workflow
    assert "0bd25a391256dbe9ad1f9c6f313364b1f9eddcc0e280c829d644034981ad8306" in workflow
    assert "openwrt-sdk-25.12.5-mediatek-mt7622_gcc-14.3.0_musl.Linux-x86_64.tar.zst" in workflow

    # The source ZIP is intended for GitHub's web uploader. Keep it below the
    # web interface limits and reject build products or SDK state in the repo.
    source_files = [
        path
        for path in ROOT.rglob("*")
        if path.is_file() and ".git" not in path.relative_to(ROOT).parts
    ]
    assert len(source_files) <= 100, len(source_files)
    assert max(path.stat().st_size for path in source_files) <= 25 * 1024 * 1024
    assert (ROOT / ".github/workflows/build.yml").is_file()
    forbidden_parts = {"build_dir", "staging_dir", "output_pkg"}
    for path in source_files:
        relative = path.relative_to(ROOT)
        assert not (forbidden_parts & set(relative.parts)), relative
        assert not any(part.startswith("openwrt-sdk") for part in relative.parts), relative
        assert path.suffix not in {".apk", ".ipk"}, relative

    # The user explicitly excluded this private firmware configuration from work.
    firmware = ROOT / "firmware-openwrt-config.txt"
    assert sha256(firmware) == "10981a9f49b60b737a72d1fa63266c7ce10b667c4f00f71c1b33d3aa4f238864"

    print("release policy tests: ok")


if __name__ == "__main__":
    main()
