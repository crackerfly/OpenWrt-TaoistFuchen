# GitHub Actions Single-APK Build Design

## Context

The repository is uploaded through GitHub's web interface and compiled by
GitHub Actions for OpenWrt 25.12.5 `mediatek/mt7622`. The target router has
working 25.12.5 package repositories and must resolve runtime dependencies
when the locally downloaded application APK is installed.

## Decision

Keep the package's direct runtime dependencies in `LUCI_DEPENDS`. They are
metadata, not embedded APKs. In particular, `kmod-nft-queue` remains direct
while `kmod-nft-core` remains transitive.

The build has three boundaries:

1. Normalize executable modes lost by GitHub web upload before tests or SDK
   copying.
2. Neutralize OpenWrt SDK package defaults, select only the application and
   the provider closure required by the pinned 25.12.5 SDK, then compile the
   application target.
3. Copy exactly one `luci-app-taoistfuchen-*.apk` into the downloadable
   artifact. Dependency APKs may exist inside the temporary SDK but must not
   enter the artifact.

The artifact continues to include the MIT/GPL license files, source
provenance and corresponding FakeHTTP/FakeSIP source archives. Those files
are compliance material, not runtime dependencies.

## Alternatives considered

### Keep the complete SDK default configuration

Rejected because the official 25.12.5 SDK selects more than one thousand
packages, including unrelated firmware. It wastes CI time and can fail on
unrelated package prerequisites.

### Remove `LUCI_DEPENDS`

Rejected because it would make the main APK smaller only on paper: the
dependencies are not embedded today. Removing the declarations would prevent
the router package solver from downloading required packages.

### Use a third-party OpenWrt build action

Rejected because the existing official-SDK workflow is already reproducible,
checksum-verifies the SDK and keeps the pinned target visible in the repo.

## Package and artifact contract

- Package: `luci-app-taoistfuchen`
- Version: `2.0.0-r2`
- Architecture: `aarch64_cortex-a53`
- Direct metadata dependencies after build:
  `cgi-io`, `coreutils-od`, `coreutils-stat`, `kmod-nft-queue`, `libc`,
  `luci-base`, `nftables`
- Download artifact: exactly one application APK plus license/provenance GPL
  source material; zero dependency APKs or IPKs
- Repository: no SDK, build directory, staging directory or built APK/IPK
- GitHub web upload: `.github/workflows/build.yml`, `README.md` and
  `luci-app-taoistfuchen/` must be at repository root

## Failure handling

The workflow fails before upload when executable normalization is incomplete,
the SDK selects unrelated firmware, package counts drift, no application APK
or multiple application APKs are found, APK metadata differs from the contract,
or any non-application APK enters the artifact directory.

## Verification

Host regression tests cover SDK-default rewriting, artifact whitelisting,
web-upload permissions and repository size/layout constraints. A real official
25.12.5 SDK build verifies the resulting APK with the SDK's `apk adbdump`.
