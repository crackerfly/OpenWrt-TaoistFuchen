#!/usr/bin/env python3

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


EXPECTED_FIELDS = {
    "name": "luci-app-taoistfuchen",
    "version": "2.0.0-r2",
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
    "luci-base",
    "nftables",
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


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} APK_TOOL APK_FILE", file=sys.stderr)
        return 2

    try:
        verify(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"APK metadata verification failed: {error}", file=sys.stderr)
        return 1

    print("APK metadata verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
