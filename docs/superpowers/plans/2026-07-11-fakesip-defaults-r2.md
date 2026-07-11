# FakeSIP Defaults for TaoistFuchen 2.1.0-r2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Release TaoistFuchen `2.1.0-r2` with FakeSIP new-install and fallback defaults set to outbound dual-stack operation while preserving every valid existing user value.

**Architecture:** Keep the existing UCI schema and FakeSIP build pipeline. Synchronize the default at the four configuration boundaries—shipped UCI, LuCI, init fallback, and uci-defaults normalization—then bump only the OpenWrt package release and rebuild the APK from the maintained source.

**Tech Stack:** OpenWrt 25.12.5 SDK, LuCI JavaScript, UCI/BusyBox shell, Python and shell regression tests, APK packaging.

## Global Constraints

- New or missing FakeSIP direction is exactly `outbound`.
- New or missing FakeSIP family is exactly `dual`.
- Existing valid `inbound`, `outbound`, `both`, `ipv4`, `ipv6`, and `dual` values are preserved.
- Invalid direction and family values normalize to `outbound` and `dual` respectively.
- Package metadata is exactly `2.1.0-r2`.
- FakeSIP remains version `0.9.4`, compiled from `luci-app-taoistfuchen/src/fakesip` by the target SDK.
- `firmware-openwrt-config.txt` remains byte-for-byte unchanged.

---

### Task 1: Lock the new defaults with failing regression tests

**Files:**
- Modify: `tests/test_release.py`
- Modify: `tests/test_service_commands.sh`
- Modify: `tests/test_migration.sh`
- Modify: `tests/test_build_pipeline.sh`

**Interfaces:**
- Consumes: current UCI files, LuCI view, init script, migration helpers, and APK verifier.
- Produces: executable assertions for new-install, missing-value, invalid-value, preservation, and `2.1.0-r2` metadata behavior.

- [ ] **Step 1: Change release-policy expectations**

In `tests/test_release.py`, require:

```python
assert "PKG_RELEASE:=2" in makefile

for needle in (
    "option direction 'outbound'",
    "option family 'dual'",
    "option port_mode 'exclude'",
    "option ports '53'",
    "option queue_num '8971'",
):
    assert needle in fakesip_cfg, needle

assert "o.default = 'outbound';" in fakesip_view
assert "o.default = 'dual';" in fakesip_view
```

- [ ] **Step 2: Add an init-fallback command test**

In `tests/test_service_commands.sh`, unset the two FakeSIP values, invoke the real `start_service`, and require the compensated outbound flag plus both address-family flags:

```sh
COMMAND_ARGS=''
NETDEVS=''
unset CFG_main_direction CFG_main_family
start_service
printf '%s\n' "$COMMAND_ARGS" | grep -Fx -- '-0' >/dev/null
if printf '%s\n' "$COMMAND_ARGS" | grep -Fx -- '-1' >/dev/null; then
    echo "FakeSIP fallback unexpectedly enabled inbound traffic" >&2
    exit 1
fi
FAMILY_ARGS="$(printf '%s\n' "$COMMAND_ARGS" | grep -E '^-4$|^-6$')"
[ "$FAMILY_ARGS" = '-4
-6' ]
```

Restore explicit values after the assertion so later validation tests stay independent:

```sh
CFG_main_direction=both
CFG_main_family=ipv4
```

- [ ] **Step 3: Expand migration tests**

Extract and exercise both `normalize_fakesip_direction()` and `normalize_fakesip_family()` from the installed script. Require missing and invalid values to become the new defaults, and loop through all valid values to prove they remain untouched:

```sh
normalize_fakesip_direction
[ "$UCI_SET" = 'fakesip.main.direction=outbound' ]

for direction in inbound outbound both; do
    UCI_DIRECTION_PRESENT=1
    UCI_DIRECTION="$direction"
    UCI_SET=''
    normalize_fakesip_direction
    [ -z "$UCI_SET" ]
done

normalize_fakesip_family
[ "$UCI_SET" = 'fakesip.main.family=dual' ]

for family in ipv4 ipv6 dual; do
    UCI_FAMILY_PRESENT=1
    UCI_FAMILY="$family"
    UCI_SET=''
    normalize_fakesip_family
    [ -z "$UCI_SET" ]
done
```

- [ ] **Step 4: Update synthetic APK fixture names and metadata**

Replace every `luci-app-taoistfuchen-2.1.0-r1.apk` fixture in `tests/test_build_pipeline.sh` with `luci-app-taoistfuchen-2.1.0-r2.apk`, and set its generated metadata to:

```yaml
version: 2.1.0-r2
```

- [ ] **Step 5: Run tests and verify RED**

Run:

```sh
python3 tests/test_release.py
sh tests/test_service_commands.sh
sh tests/test_migration.sh
sh tests/test_build_pipeline.sh
```

Expected: failures reference the current `PKG_RELEASE:=1`, FakeSIP `both`/`ipv4` defaults, migration fallback to IPv4, or verifier expectation `2.1.0-r1`. Failures must be assertion failures caused by the old behavior rather than syntax errors.

---

### Task 2: Implement synchronized outbound dual-stack defaults

**Files:**
- Modify: `luci-app-taoistfuchen/Makefile`
- Modify: `luci-app-taoistfuchen/root/etc/config/fakesip`
- Modify: `luci-app-taoistfuchen/htdocs/luci-static/resources/view/taoistfuchen/fakesip.js`
- Modify: `luci-app-taoistfuchen/root/etc/init.d/fakesip`
- Modify: `luci-app-taoistfuchen/root/etc/uci-defaults/99_taoistfuchen`
- Modify: `scripts/verify-built-apk.py`
- Modify: `README.md`
- Modify: `GITHUB_WEB_UPLOAD.md`

**Interfaces:**
- Consumes: UCI options `fakesip.main.direction` and `fakesip.main.family`.
- Produces: `outbound`/`dual` defaults and the existing compensated command sequence `-0 -4 -6`.

- [ ] **Step 1: Bump the package release and verifier metadata**

Set:

```make
PKG_VERSION:=2.1.0
PKG_RELEASE:=2
```

Set the verifier metadata in `scripts/verify-built-apk.py` to:

```python
"version": "2.1.0-r2",
```

- [ ] **Step 2: Change shipped UCI and LuCI defaults**

Set the shipped config to:

```uci
option direction 'outbound'
option family 'dual'
```

Keep all three choices visible in LuCI, label outbound and dual-stack as the defaults, retain the IPv6 extension-header warning, and set:

```javascript
o.default = 'outbound';
o.default = 'dual';
```

- [ ] **Step 3: Change both init-script fallback sites**

In validation and `start_service()`, use:

```sh
config_get direction main direction 'outbound'
config_get family main family 'dual'
```

Do not change the established direction compensation: UI `outbound` continues to append `-0`, and `dual` continues to append `-4 -6`.

- [ ] **Step 4: Normalize only missing or invalid migration values**

Add a direction normalizer and update the family normalizer:

```sh
normalize_fakesip_direction() {
    local direction

    direction="$(uci -q get fakesip.main.direction 2>/dev/null || true)"
    case "$direction" in
        inbound|outbound|both) return 0 ;;
        '') ;;
        *) logger -t taoistfuchen "resetting invalid FakeSIP traffic direction to outbound" 2>/dev/null || true ;;
    esac
    uci -q set fakesip.main.direction=outbound
}
```

The family helper uses the same pattern but logs and assigns `dual`. Replace the prior `set_default fakesip main direction both` call with `normalize_fakesip_direction`, then call `normalize_fakesip_family`. Do not inspect or rewrite valid values.

- [ ] **Step 5: Update user documentation**

Document FakeSIP's default command as:

```sh
fakesip -0 -4 -6 -i <WAN设备> \
  -P 53 -r 2 -t 3 -n 8971 -m 0x10000 -x 0x10000 -s
```

Explain that upgrades preserve existing valid selections. Change download examples and Actions artifact names from `2.1.0-r1` to `2.1.0-r2`.

- [ ] **Step 6: Run targeted and full tests to verify GREEN**

Run:

```sh
python3 tests/test_release.py
sh tests/test_service_commands.sh
sh tests/test_migration.sh
sh tests/test_build_pipeline.sh
./tests/run.sh
sha256sum -c third_party/SHA256SUMS
git diff --check
```

Expected: all commands exit 0 and report their corresponding `ok` messages.

- [ ] **Step 7: Commit the implementation**

```sh
git add -A
git commit -m "fix: default FakeSIP to outbound dual stack"
```

---

### Task 3: Rebuild and verify the real 2.1.0-r2 APK

**Files:**
- Read: `.github/workflows/build.yml`
- Read: `scripts/configure-openwrt-sdk.sh`
- Read: `scripts/prepare-artifact.sh`
- Read: `scripts/verify-built-apk.py`
- Generate outside Git: `luci-app-taoistfuchen-2.1.0-r2.apk`
- Generate outside Git: `OpenWrt-TaoistFuchen-v2.1.0-r2-source.zip`
- Generate outside Git: `luci-app-taoistfuchen-2.1.0-r2-Actions-artifact.zip`

**Interfaces:**
- Consumes: committed package source and the official OpenWrt 25.12.5 `mediatek/mt7622` SDK.
- Produces: one verified application APK and upload-ready source/Actions ZIPs.

- [ ] **Step 1: Copy the committed package into a clean SDK package directory**

Use the same SDK version and feed pins as `.github/workflows/build.yml`, copy `luci-app-taoistfuchen` into `openwrt-sdk/package/`, and run `scripts/configure-openwrt-sdk.sh` so only the application and its real dependency closure are selected.

- [ ] **Step 2: Compile the package with verbose single-job output**

Run from the SDK:

```sh
make package/luci-app-taoistfuchen/clean
make package/luci-app-taoistfuchen/compile -j1 V=s
```

Expected: exit 0 and exactly one main package named `luci-app-taoistfuchen-2.1.0-r2.apk`.

- [ ] **Step 3: Verify the real APK payload**

Run:

```sh
python3 scripts/verify-built-apk.py \
  openwrt-sdk/staging_dir/host/bin/apk \
  openwrt-sdk/bin/packages/aarch64_cortex-a53/base/luci-app-taoistfuchen-2.1.0-r2.apk
```

Extract it and require:

```text
/usr/bin/fakesip: ELF 64-bit LSB executable, ARM aarch64
FakeSIP version 0.9.4
```

The ELF dynamic section must require `libnetfilter_queue.so.1`, `libnfnetlink.so.0`, and `libmnl.so.0`.

- [ ] **Step 4: Generate and re-test deliverables**

Use `scripts/prepare-artifact.sh` to generate an Actions-style directory containing exactly one APK, licenses, and corresponding source archives. Generate the source ZIP from Git `HEAD`, extract it into a temporary directory, run `./tests/run.sh` there, and validate every published hash with `sha256sum -c SHA256SUMS`.

- [ ] **Step 5: Report exact hashes and upload instructions**

Report the SHA-256 values of the r2 APK, source ZIP, Actions artifact ZIP, and checksum manifest. Tell the user to extract the source ZIP and upload the inner contents—including `.github/workflows/build.yml`—to the GitHub repository root.
