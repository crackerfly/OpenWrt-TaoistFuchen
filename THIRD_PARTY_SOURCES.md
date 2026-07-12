# Third-party binary and source provenance

This repository redistributes one unmodified, statically linked AArch64
FakeHTTP release binary and builds a project-maintained FakeSIP from source.
Both are licensed under GNU GPLv3. Corresponding source archives are included
under `third_party/sources/` and verified by `third_party/SHA256SUMS`.

## FakeHTTP 0.9.18

- Project: <https://github.com/MikeWang000000/FakeHTTP>
- Release: <https://github.com/MikeWang000000/FakeHTTP/releases/tag/0.9.18>
- Source tag commit: `cf941f1a1ae06b1bea53e4389f9729a969452ec7`
- Bundled release asset: `fakehttp-linux-arm64.tar.gz`
- Bundled binary SHA-256:
  `2a48dc7c1d61a582f438acad1c416414e8946d36dba72ddb0861b28e98e6d82c`
- Corresponding source archive: `third_party/sources/FakeHTTP-0.9.18.tar.gz`

## TaoistFuchen-maintained FakeSIP 0.9.5

- Project: <https://github.com/Droid-MAX/FakeSIP>
- Upstream baseline commit:
  `bb6fdd88e7fa6f6d4fb1b02e359e5e68c7d778b6` (the 0.9.3 release source)
- Maintained build source: `luci-app-taoistfuchen/src/fakesip/`
- Corresponding source archive:
  `third_party/sources/FakeSIP-TaoistFuchen-0.9.5.tar.gz`
- Source archive SHA-256:
  `cb8c4e77beee0a360d5dad77cde012da19dccea6fac8c8eb6eafc38d921c33a0`
- Build: compiled by the pinned OpenWrt SDK as part of
  `luci-app-taoistfuchen`; no precompiled FakeSIP executable is stored in the
  repository.

The 0.9.4 packet-path maintenance delta is intentionally small:

- use `icmpv6 type time-exceeded` in the nftables IPv6 table;
- submit the generated IPv6 nft batch once;
- encode valid IPv4 and IPv6 UDP lengths, including the UDP header;
- clean partial firewall state after a failed dual-stack setup;
- scope ICMP Time Exceeded drops to the selected inbound interfaces;
- stop raw re-injection of the original outbound datagram and accept its queued
  skb after the decoys, avoiding duplicates while preserving kernel metadata;
- use a signal-safe termination flag for clean procd shutdown.

Version 0.9.5 leaves that packet path unchanged. It corrects the CLI help and
startup log so the legacy `-0`/`-1` fields report their actual outbound/inbound
packet directions, and it explicitly reports single-stack or dual-stack mode.

FakeSIP's general behavior and base CLI are documented by the original project at
<https://github.com/MikeWang000000/FakeSIP/wiki>. The Droid-MAX baseline adds
`-p`/`-P` UDP port filters. Version 0.9.5 retains one known limitation: it does
not parse IPv6 extension headers before UDP.

## Rebuilding the upstream tools

FakeHTTP's source snapshot uses its upstream Makefile. With an AArch64 musl
toolchain and the required static libraries available, run:

```sh
make clean
make CROSS_PREFIX=aarch64-openwrt-linux-musl- STATIC=1 VERSION=0.9.18
```

FakeSIP 0.9.5 is built through LuCI's standard `src/Makefile` integration. The
reproducible supported path is the pinned SDK workflow in
`.github/workflows/build.yml`; it supplies the target compiler and links against
OpenWrt's packaged `libnetfilter-queue`. The built APK declares that shared
library as an external runtime dependency, and the artifact collector still
publishes only the application APK.
