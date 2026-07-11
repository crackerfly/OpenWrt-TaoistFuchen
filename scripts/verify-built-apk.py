#!/usr/bin/env python3

from __future__ import annotations

import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


EXPECTED_FIELDS = {
    "name": "luci-app-taoistfuchen",
    "version": "2.1.0-r2",
    "arch": "aarch64_cortex-a53",
    "maintainer": "Hevil",
    "url": "https://github.com/crackerfly/OpenWrt-TaoistFuchen",
}
EXPECTED_LICENSES = {"MIT", "GPL-3.0-or-later"}
EXPECTED_DEPENDS = {
    "cgi-io",
    "coreutils-od",
    "coreutils-stat",
    "kmod-nft-queue",
    "libc",
    "libnetfilter-queue1",
    "luci-base",
    "nftables",
}
EXPECTED_FAKESIP_NEEDED = {
    "libc.so",
    "libgcc_s.so.1",
    "libmnl.so.0",
    "libnetfilter_queue.so.1",
    "libnfnetlink.so.0",
}


def parse_adbdump(output: str) -> tuple[dict[str, str], set[str]]:
    fields: dict[str, str] = {}
    depends: set[str] = set()
    in_depends = False

    for line in output.splitlines():
        field = re.match(r"^  ([a-z][a-z0-9-]*):(?:\s*(.*))?$", line)
        if field:
            name, value = field.groups()
            in_depends = name == "depends"
            if name != "depends" and value is not None:
                fields[name] = value.strip()
            continue

        if in_depends:
            dependency = re.match(r"^    -\s+([^\s]+)\s*$", line)
            if dependency:
                depends.add(dependency.group(1))
            elif line and not line.startswith("    "):
                in_depends = False

    return fields, depends


def verify_fakesip_payload(apk_tool: Path, apk_file: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="taoistfuchen-apk-") as directory:
        destination = Path(directory)
        # `apk extract` validates the file that users will install, rather than
        # trusting an unstripped intermediate from the SDK build directory.
        subprocess.run(
            [
                str(apk_tool),
                "--allow-untrusted",
                "extract",
                "--no-chown",
                "--destination",
                str(destination),
                str(apk_file),
            ],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        binary = destination / "usr/bin/fakesip"
        if binary.is_symlink() or not binary.is_file():
            raise ValueError("APK does not contain a regular usr/bin/fakesip")
        mode = stat.S_IMODE(binary.stat().st_mode)
        if mode != 0o755:
            raise ValueError(f"unexpected fakesip mode: {mode:o} (expected 755)")

        contents = binary.read_bytes()
        if len(contents) < 20 or contents[:4] != b"\x7fELF":
            raise ValueError("fakesip is not an ELF executable")
        if contents[4] != 2 or contents[5] != 1:
            raise ValueError("fakesip is not a 64-bit little-endian ELF")
        machine = int.from_bytes(contents[18:20], byteorder="little")
        if machine != 183:  # EM_AARCH64
            raise ValueError(f"unexpected fakesip ELF machine: {machine}")

        for marker in (
            b"/lib/ld-musl-aarch64.so.1",
            b"FakeSIP version 0.9.4",
            b"icmpv6 type time-exceeded counter drop",
        ):
            if marker not in contents:
                raise ValueError(f"missing fakesip payload marker: {marker!r}")

        readelf = os.environ.get("READELF", "readelf")
        result = subprocess.run(
            [readelf, "-d", str(binary)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        needed = set(
            re.findall(r"\(NEEDED\).*Shared library: \[([^]]+)\]", result.stdout)
        )
        if needed != EXPECTED_FAKESIP_NEEDED:
            raise ValueError(
                f"unexpected fakesip DT_NEEDED: {sorted(needed)} "
                f"(expected {sorted(EXPECTED_FAKESIP_NEEDED)})"
            )


def verify(apk_tool: Path, apk_file: Path) -> None:
    if not apk_tool.is_file():
        raise ValueError(f"APK tool not found: {apk_tool}")
    if not apk_file.is_file():
        raise ValueError(f"APK file not found: {apk_file}")

    result = subprocess.run(
        [str(apk_tool), "adbdump", str(apk_file)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    fields, depends = parse_adbdump(result.stdout)

    for name, expected in EXPECTED_FIELDS.items():
        actual = fields.get(name)
        if actual != expected:
            raise ValueError(f"unexpected {name}: {actual!r} (expected {expected!r})")

    licenses = set(fields.get("license", "").split())
    if licenses != EXPECTED_LICENSES:
        raise ValueError(
            f"unexpected licenses: {sorted(licenses)} "
            f"(expected {sorted(EXPECTED_LICENSES)})"
        )

    if depends != EXPECTED_DEPENDS:
        raise ValueError(
            f"unexpected dependencies: {sorted(depends)} "
            f"(expected {sorted(EXPECTED_DEPENDS)})"
        )

    verify_fakesip_payload(apk_tool, apk_file)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} APK_TOOL APK_FILE", file=sys.stderr)
        return 2

    try:
        verify(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"APK metadata verification failed: {error}", file=sys.stderr)
        return 1

    print("APK metadata and FakeSIP payload verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
