# GitHub Actions Single-APK Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a GitHub-web-uploaded repository build one installable OpenWrt 25.12.5 application APK while keeping runtime dependencies external and solver-installable.

**Architecture:** Small repository scripts own permission normalization, SDK
configuration, APK metadata verification and artifact collection. The workflow
orchestrates those scripts. The package Makefile remains the single source of
runtime dependency metadata.

**Tech Stack:** POSIX shell, awk, Python 3, GitHub Actions YAML, OpenWrt 25.12.5 SDK/APK v3.

## Global Constraints

- Keep `LUCI_DEPENDS:=+luci-base +cgi-io +nftables +kmod-nft-queue +coreutils-stat +coreutils-od`.
- Do not add `kmod-nft-core` as a direct dependency.
- Artifact contains exactly one `luci-app-taoistfuchen-*.apk` and no dependency APK/IPK.
- Keep GPL corresponding source archives and license/provenance files.
- Support GitHub web upload where executable bits arrive as 0644.
- Pin build to OpenWrt 25.12.5 `mediatek/mt7622` and package architecture `aarch64_cortex-a53`.

---

### Task 1: Build-pipeline regression tests

**Files:**
- Create: `tests/test_build_pipeline.sh`
- Modify: `tests/run.sh`
- Modify: `tests/test_release.py`

**Interfaces:**
- Consumes: repository layout, package Makefile and workflow text.
- Produces: failing behavioral checks for SDK default minimization, single-APK collection, web-upload permissions and repository cleanliness.

- [ ] Write a shell fixture with unrelated `default m/y` package symbols and the pinned kmod provider symbols.
- [ ] Invoke the not-yet-existing SDK minimizer and assert unrelated defaults become `n` while the pinned provider closure is retained.
- [ ] Build a fake SDK output containing the main APK and dependency APKs, invoke the not-yet-existing collector and assert only the main APK is copied.
- [ ] Add a duplicate-main-APK case and assert collection fails.
- [ ] Add release-policy assertions for workflow order, exact dependencies, root layout, file-count/size limits and absence of generated package/build files.
- [ ] Run `./tests/run.sh` and confirm failure is caused by missing build-pipeline scripts.

### Task 2: Build scripts and workflow

**Files:**
- Create: `scripts/normalize-source-permissions.sh`
- Create: `scripts/minimize-sdk-config.awk`
- Create: `scripts/configure-openwrt-sdk.sh`
- Create: `scripts/verify-built-apk.py`
- Create: `scripts/prepare-artifact.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- `normalize-source-permissions.sh` takes no arguments and restores all runtime/test/build script executable modes.
- `configure-openwrt-sdk.sh SDK_DIR` rewrites SDK defaults, seeds `.config`, runs `make defconfig` and enforces the pinned package-count contract.
- `verify-built-apk.py APK_TOOL APK_FILE` parses `apk adbdump` and enforces name, version, architecture, maintainer, URL, license and exact dependencies.
- `prepare-artifact.sh SDK_DIR OUTPUT_DIR` verifies and copies exactly one main APK plus compliance files.

- [ ] Implement permission normalization with explicit paths.
- [ ] Implement SDK default rewriting and the pinned 25.12.5 provider closure.
- [ ] Implement exact APK metadata parsing and validation without third-party Python modules.
- [ ] Implement artifact collection with an exact-one match and output whitelist.
- [ ] Replace long inline workflow logic with calls to the scripts, keeping official SDK checksum validation and feed setup.
- [ ] Run `./tests/run.sh` and confirm all build-pipeline tests pass.

### Task 3: Package metadata and user instructions

**Files:**
- Modify: `luci-app-taoistfuchen/Makefile`
- Modify: `README.md`
- Create: `GITHUB_WEB_UPLOAD.md`

**Interfaces:**
- Produces: `2.0.0-r2` metadata with `LUCI_MAINTAINER`/`LUCI_URL`, plus end-to-end upload, Actions download and one-APK installation instructions.

- [ ] Bump `PKG_RELEASE` to `2`, replace ignored `PKG_MAINTAINER` with `LUCI_MAINTAINER`, and set the project `LUCI_URL`.
- [ ] Document that users upload the extracted directory contents, including hidden `.github`, into repository root.
- [ ] Document that Actions may build temporary dependency APKs but uploads only the main APK.
- [ ] Document `apk update` and local `apk add --allow-untrusted /tmp/luci-app-taoistfuchen-*.apk`, with automatic repository dependency resolution and kernel-ABI caveat.
- [ ] Run release and complete regression tests.

### Task 4: Real build and deliverable verification

**Files:**
- Create deliverables only; do not add SDK/build output to git.

**Interfaces:**
- Produces: source ZIP and a locally verified `2.0.0-r2` APK.

- [ ] Run an official OpenWrt 25.12.5 `mediatek/mt7622` SDK build with the same scripts used by Actions.
- [ ] Run APK metadata verification and inspect the artifact whitelist.
- [ ] Re-run all tests from a clean source archive extraction.
- [ ] Generate SHA-256 values for the final source ZIP and APK.
- [ ] Save the final source ZIP and APK as user-facing deliverables.
