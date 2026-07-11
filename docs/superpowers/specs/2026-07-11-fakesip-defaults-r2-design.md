# FakeSIP Default Settings for TaoistFuchen 2.1.0-r2

## Goal

Change the FakeSIP defaults to router-oriented outbound dual-stack operation:

- traffic direction: `outbound`
- address family: `dual` (IPv4 and IPv6)

The package version remains TaoistFuchen 2.1.0 and the OpenWrt package release
increments from `r1` to `r2` so an installed r1 package can be upgraded.

## Configuration semantics

The shipped `/etc/config/fakesip`, LuCI form defaults, init-script fallback
values, and uci-defaults fallback values all use `outbound` and `dual`.

The upgrade migration follows a preserve-valid-values policy:

- any existing valid direction (`inbound`, `outbound`, or `both`) is preserved;
- any existing valid family (`ipv4`, `ipv6`, or `dual`) is preserved;
- a missing or invalid direction is set to `outbound`;
- a missing or invalid family is set to `dual`.

The migration does not rewrite the old `both` plus `ipv4` combination because
it cannot distinguish an inherited default from an intentional user choice.

## Build and packaging

The FakeSIP build path is unchanged. GitHub Actions copies this package into the
OpenWrt 25.12.5 SDK, which invokes `luci-app-taoistfuchen/src/Makefile`. That
wrapper builds the maintained FakeSIP 0.9.4 source with the target compiler and
installs the resulting executable as `/usr/bin/fakesip` inside the application
APK. Runtime shared-library dependencies remain resolved by OpenWrt APK.

## Verification

Regression tests must verify:

- new-install defaults are `outbound` and `dual`;
- init-script missing-value fallbacks produce the outbound and dual-stack
  command flags;
- missing and invalid upgrade values migrate to the new defaults;
- every valid pre-existing direction and family value remains unchanged;
- the package metadata is `2.1.0-r2`;
- the built APK contains an executable AArch64 FakeSIP 0.9.4 binary.
