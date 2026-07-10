# Third-party binary and source provenance

This repository redistributes two unmodified, statically linked AArch64 release
binaries under GNU GPLv3. The corresponding source snapshots are included under
`third_party/sources/` and verified by `third_party/SHA256SUMS`.

## FakeHTTP 0.9.18

- Project: <https://github.com/MikeWang000000/FakeHTTP>
- Release: <https://github.com/MikeWang000000/FakeHTTP/releases/tag/0.9.18>
- Source tag commit: `cf941f1a1ae06b1bea53e4389f9729a969452ec7`
- Bundled release asset: `fakehttp-linux-arm64.tar.gz`
- Bundled binary SHA-256:
  `2a48dc7c1d61a582f438acad1c416414e8946d36dba72ddb0861b28e98e6d82c`
- Corresponding source archive: `third_party/sources/FakeHTTP-0.9.18.tar.gz`

## Droid-MAX/FakeSIP 0.9.3

- Project: <https://github.com/Droid-MAX/FakeSIP>
- Release: <https://github.com/Droid-MAX/FakeSIP/releases/tag/0.9.3>
- Source tag commit: `bb6fdd88e7fa6f6d4fb1b02e359e5e68c7d778b6`
- Bundled release asset: `fakesip-linux-arm64.tar.gz`
- Bundled binary SHA-256:
  `3f49b5ef397dc0b5127ab5860668110309176787b1dafb5c1fa4ef55d39580b7`
- Corresponding source archive:
  `third_party/sources/FakeSIP-Droid-MAX-0.9.3.tar.gz`

FakeSIP's general behavior and base CLI are documented by the original project at
<https://github.com/MikeWang000000/FakeSIP/wiki>. The redistributed 0.9.3 binary is
specifically the Droid-MAX release, which adds `-p`/`-P` UDP port filters.

## Rebuilding the upstream tools

Both source snapshots use the upstream Makefile. With an AArch64 musl toolchain
whose prefix is available in `PATH`, install static versions of libnetfilter_queue,
libnfnetlink and libmnl for that toolchain, then run:

```sh
make clean
make CROSS_PREFIX=aarch64-openwrt-linux-musl- STATIC=1 VERSION=0.9.18
```

For FakeSIP use `VERSION=0.9.3`. Toolchain and library versions affect the final
static ELF bytes, so release identity is checked against the publishers' arm64
assets using the binary SHA-256 values above.

