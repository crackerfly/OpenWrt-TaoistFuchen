#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import re
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
    assert "PKG_VERSION:=2.1.0" in makefile
    assert "PKG_RELEASE:=3" in makefile
    assert "FakeSIP 0.9.5" in makefile
    assert "LUCI_PKGARCH:=aarch64_cortex-a53" in makefile
    assert (
        "LUCI_DEPENDS:=+luci-base +cgi-io +nftables +kmod-nft-queue "
        "+coreutils-stat +coreutils-od +flock +libnetfilter-queue"
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
        "option boot_delay '60'",
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
        "option boot_delay '40'",
        "option direction 'outbound'",
        "option family 'dual'",
        "option port_mode 'exclude'",
        "option ports '53'",
        "option queue_num '8971'",
    ):
        assert needle in fakesip_cfg, needle
    assert "list interface ''" not in fakesip_cfg

    fakehttp_init = text(PKG / "root/etc/init.d/fakehttp")
    fakesip_init = text(PKG / "root/etc/init.d/fakesip")
    boot_scheduler_path = PKG / "root/etc/init.d/taoistfuchen-boot-delay"
    boot_runner_path = PKG / "root/usr/share/taoistfuchen/boot-delay-runner.sh"
    assert boot_scheduler_path.is_file()
    assert boot_runner_path.is_file()
    boot_scheduler = text(boot_scheduler_path)
    boot_runner = text(boot_runner_path)
    assert "START=98" in boot_scheduler
    assert "STOP=09" in boot_scheduler
    assert "respawn" not in boot_scheduler
    assert "boot_expired" in boot_runner
    assert "tf_boot_state_set" not in boot_runner
    for init, prefix in ((fakehttp_init, "fh"), (fakesip_init, "fs")):
        assert "boot()" not in init
        assert "sleep " not in init
        assert "procd_add_reload_trigger" in init
        assert "service_stopped()" in init
        assert "-w" not in init
        for command in ("link_down", "link_up", "boot_expired"):
            assert command in init
        assert "stop_service()" in init
        assert "reload_service()" in init
        assert "procd_kill \"$SERVICE_NAME\"" in init
        locked_start = init.split(f"{prefix}_start_service_locked()", 1)[1].split(
            "\nstart_service()", 1
        )[0]
        assert not re.search(r"^\s*procd_kill\b", locked_start, re.MULTILINE)
        isolated_kill = '( procd_kill "$SERVICE_NAME" )'
        assert isolated_kill in locked_start
        assert locked_start.index(isolated_kill) < locked_start.index(
            'tf_cleanup_nft_table "$SERVICE_NAME"'
        )
    assert "-1" in fakehttp_init
    assert "-0" in fakesip_init and "-1" in fakesip_init
    assert "ipv4|ipv6|dual" in fakesip_init
    assert "procd_append_param command -4 -6" in fakesip_init
    assert "-P" in fakesip_init and "0x10000" in fakesip_init

    hotplug = text(PKG / "root/etc/hotplug.d/iface/99-taoistfuchen")
    assert "network_get_device" in hotplug
    assert "tf_hotplug_device_cache_set" in hotplug
    assert "tf_hotplug_device_cache_get" in hotplug
    assert "link_down" in hotplug and "link_up" in hotplug
    assert " reload" not in hotplug
    for managed_script in (fakehttp_init, fakesip_init, hotplug, boot_scheduler, boot_runner):
        assert not re.search(r"\bsleep[^\n]*&", managed_script)
        assert not re.search(r"\(\s*sleep[\s\S]{0,200}?\)\s*&", managed_script)

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
    assert "uci -q delete fakehttp.main.boot_delay" not in defaults
    assert "uci -q delete fakesip.main.boot_delay" not in defaults
    assert "migrate_r3_boot_delays" in defaults
    assert "taoistfuchen.main.boot_delay_migrated_r3" in defaults
    assert "boot_delay_migrated_r3" not in text(PKG / "root/etc/config/taoistfuchen")
    assert "/var/run/taoistfuchen-upload" in defaults
    assert "/etc/init.d/taoistfuchen-boot-delay" in defaults
    assert "/usr/share/taoistfuchen/boot-delay-runner.sh" in defaults
    assert "TAOISTFUCHEN_SERVICE_CONTEXT=auto" in defaults
    assert "taoistfuchen-boot-delay" in defaults
    assert "sleep " not in text(PKG / "root/etc/hotplug.d/iface/99-taoistfuchen")

    for executable in (
        PKG / "root/usr/bin/fakehttp",
        PKG / "root/etc/init.d/taoistfuchen",
        PKG / "root/etc/init.d/fakehttp",
        PKG / "root/etc/init.d/fakesip",
        boot_scheduler_path,
        boot_runner_path,
        PKG / "root/etc/uci-defaults/99_taoistfuchen",
        PKG / "root/www/cgi-bin/taoistfuchen-upload",
    ):
        assert executable.stat().st_mode & stat.S_IXUSR, f"not executable: {executable}"

    assert "taoistfuchen-boot-delay fakehttp fakesip taoistfuchen" in makefile
    assert "/var/run/taoistfuchen-boot-delay" in makefile

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
    assert "FakeSIP 0.9.5" in sources
    assert "2a48dc7c1d61a582" in sources
    assert (ROOT / "third_party/sources/FakeHTTP-0.9.18.tar.gz").is_file()
    assert (ROOT / "third_party/sources/FakeSIP-TaoistFuchen-0.9.5.tar.gz").is_file()
    assert not (ROOT / "third_party/sources/FakeSIP-TaoistFuchen-0.9.4.tar.gz").exists()
    assert not (PKG / "root/usr/bin/fakesip").exists()

    fakesip_view = text(PKG / "htdocs/luci-static/resources/view/taoistfuchen/fakesip.js")
    assert "FakeSIP 0.9.5" in fakesip_view
    assert "form.ListValue, 'family'" in fakesip_view
    for family in ("ipv4", "ipv6", "dual"):
        assert f"o.value('{family}'" in fakesip_view
    assert "IPv6 extension headers" in fakesip_view
    assert "IPv4 only (enforced)" not in fakesip_view
    assert "_family" not in fakesip_view
    assert "o.default = 'outbound';" in fakesip_view
    assert "o.default = 'dual';" in fakesip_view

    readme = text(ROOT / "README.md")
    for needle in ("FakeHTTP 0.9.18", "FakeSIP 0.9.5"):
        assert needle in readme
    for needle in (
        "FakeSIP 默认 40 秒",
        "FakeHTTP 默认 60 秒",
        "0–600 秒",
        "`0` 表示开机也不延迟",
        "页面和命令行的人工启停立即执行",
        "两个等待任务并行计时",
        "`ifdown` 使用专用 stop-only 路径",
        "`ifup` 使用独立恢复路径",
        "开机窗口内保持等待",
        "第一次安装或升级到 r3",
        "同一 r3 重装",
    ):
        assert needle in readme, needle
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
        "luci-app-taoistfuchen-2.1.0-r3.apk",
        "flock",
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

    normalizer = text(ROOT / "scripts/normalize-source-permissions.sh")
    assert "boot-delay-runner.sh" in normalizer

    sdk_configurer = text(ROOT / "scripts/configure-openwrt-sdk.sh")
    assert '"$module_count" -eq 12' in sdk_configurer
    for expected in (
        "libmnl=y",
        "flock=m",
        "libnetfilter-queue=m",
        "libnfnetlink=m",
        "libattr=y",
        "libacl=y",
        "libcap=y",
        "libpthread=m",
        "librt=m",
    ):
        assert expected in sdk_configurer

    apk_verifier = text(ROOT / "scripts/verify-built-apk.py")
    for expected in (
        "apk extract",
        "usr/bin/fakesip",
        '"version": "2.1.0-r3"',
        '"flock"',
        "FakeSIP version 0.9.5",
        "process outbound packets",
        "process inbound packets",
        "IPv4 only",
        "IPv6 only",
        "IPv4 and IPv6",
        "outbound only",
        "inbound only",
        "inbound and outbound",
        "icmpv6 type time-exceeded counter drop",
        "libnetfilter_queue.so.1",
        "libnfnetlink.so.0",
        "libmnl.so.0",
    ):
        assert expected in apk_verifier

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
