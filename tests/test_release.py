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
    assert "LUCI_PKGARCH:=aarch64_cortex-a53" in makefile
    assert "+nftables" in makefile and "+cgi-io" in makefile
    assert "+coreutils-stat" in makefile and "+coreutils-od" in makefile
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

    workflow = text(ROOT / ".github/workflows/build.yml")
    assert "third_party/sources/*.tar.gz output_pkg/" in workflow
    assert "luci-app-taoistfuchen/COPYING" in workflow
    assert "luci-app-taoistfuchen/LICENSE" in workflow

    # The user explicitly excluded this private firmware configuration from work.
    firmware = ROOT / "firmware-openwrt-config.txt"
    assert sha256(firmware) == "10981a9f49b60b737a72d1fa63266c7ce10b667c4f00f71c1b33d3aa4f238864"

    print("release policy tests: ok")


if __name__ == "__main__":
    main()
