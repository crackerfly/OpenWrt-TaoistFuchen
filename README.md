# Taoist Fuchen (luci-app-taoistfuchen)

A small LuCI "toolbox" app for OpenWrt 24.10 and 25.12. It bundles three tools
under one **Services -> Taoist Fuchen** menu:

1. **Custom Logo** – upload and replace the Web UI favicon and navigation-bar logo.
2. **FakeHTTP** – disguise outgoing **TCP** connections as HTTP traffic to evade DPI.
3. **FakeSIP** – disguise outgoing **UDP** traffic as SIP traffic to evade DPI.

FakeHTTP and FakeSIP are open-source tools by MikeWang000000. This package ships
their prebuilt **aarch64 (arm64)** binaries, so it is built specifically for the
**MediaTek mt7622** target (e.g. the **Linksys E8450 / Belkin RT3200**).

---

## 1. Custom Logo

Upload and independently replace:

- Web UI favicon — `.ico` / `.png` / `.svg`, max `512 KB` (use `.ico` for the most
  compatible `/favicon.ico` replacement)
- Navigation-bar logo — `.png` / `.svg`, max `1024 KB` (SVG recommended)

Uploaded files are stored under `/etc/taoistfuchen`. Optimized for the **Bootstrap**
and **Argon** themes. Original theme files are backed up with a `.backup` suffix and
restored automatically when the feature is disabled or the package is removed.

To restore defaults: open **Services -> Taoist Fuchen -> Custom Logo**, turn it off,
and click *Save & Apply*.

## 2. FakeHTTP

FakeHTTP makes your outgoing TCP connections look like ordinary HTTP traffic so that
Deep Packet Inspection (DPI) has a harder time fingerprinting them. It only acts
during the TCP handshake; it is **not** a tunnel or proxy and does not change where
your traffic goes.

Settings (**Services -> Taoist Fuchen -> FakeHTTP**):

- **Enable** – turn the service on/off.
- **Network interface** – the Internet-facing interface (the device your traffic
  leaves through). For PPPoE this is usually `pppoe-wan`; otherwise your WAN device.
  The page lists your real interfaces and also lets you type a name. The package
  tries to auto-detect and pre-fill your WAN device on install.
- **Obfuscation hostname** – the domain your connections are disguised as. Pre-filled
  with `www.speedtest.net`.

Internally the service runs:

```sh
fakehttp -i <interface> -h <hostname> -s -n 8970 -w /tmp/fakehttp.log
```

## 3. FakeSIP

FakeSIP makes your outgoing UDP traffic look like ordinary SIP (VoIP) traffic. Like
FakeHTTP, it only acts during the early stage of a UDP exchange and is not a tunnel.

Settings (**Services -> Taoist Fuchen -> FakeSIP**):

- **Enable** – turn the service on/off.
- **Network interface** – same idea as FakeHTTP above.

Internally the service runs:

```sh
fakesip -i <interface> -s -n 8971 -w /tmp/fakesip.log
```

### Running both at once

FakeHTTP and FakeSIP each create their own nftables tables (`fakehttp` / `fakesip`)
and are pinned to **different netfilter queue numbers** (`8970` and `8971`). Because
of this they can be enabled **at the same time** without conflicting. (Each tool
still cannot run more than one copy of itself — that is a limitation of the tools.)

## Logging

Each service writes its run log to a file in `/tmp` (which lives in RAM, so the
router's flash is never touched):

- `/tmp/fakehttp.log`
- `/tmp/fakesip.log`

You can read these logs directly on each tool's settings page — there is a live
**Run log** panel that refreshes every few seconds, plus a **Clear log** button.

The `-s` (silent) flag is used so the logs record operational events (startup, the
interface and queue in use, warnings, errors) but **not** every client IP address.
This keeps the logs small and protects privacy. If you would rather log full
per-connection activity, remove `-s` from the two init scripts — but watch the size.

To stop logs from ever filling RAM, a cron job runs every 30 minutes and trims each
log back down once it grows past ~128 KB (keeping the most recent ~64 KB). The logs
also disappear on reboot, since `/tmp` is volatile.

## Dependencies

- `kmod-nft-queue` – the NFQUEUE kernel module FakeHTTP/FakeSIP need. It is **not**
  part of the base system, so the package pulls it in automatically.
- `nftables` (the `nft` userspace) – also required at runtime, **but it is already
  part of every standard OpenWrt install** (it is the firewall4 backend). It is
  therefore **intentionally not listed as a package dependency**, so that
  uninstalling this app can never remove your firewall backend.

> If `kmod-nft-queue` cannot be installed with an error like
> *"cannot find dependency kernel (= ...)"*, your opkg/apk feeds are misconfigured
> or your firmware lacks the matching kernel module. Update your package feeds, or
> rebuild firmware with `CONFIG_PACKAGE_kmod-nft-queue=y` and
> `CONFIG_PACKAGE_kmod-nfnetlink-queue=y`.

## Build

This package is **architecture-specific** (it bundles arm64 binaries) and must be
built with the **mt7622** SDK. The included GitHub Actions workflow builds it for
`mediatek/mt7622` on OpenWrt 24.10.6 and 25.12.4.

To build manually:

```sh
cp -a luci-app-taoistfuchen openwrt-sdk/package/
cd openwrt-sdk
./scripts/feeds update -a
./scripts/feeds install -a
make defconfig
make package/luci-app-taoistfuchen/compile V=s
```

Output is under `bin/packages/`. OpenWrt 24.10 produces `.ipk`; 25.12 produces `.apk`.

## Install

OpenWrt 24.10:

```sh
opkg install luci-app-taoistfuchen_*.ipk
```

OpenWrt 25.12:

```sh
apk add --allow-untrusted luci-app-taoistfuchen_*.apk
```

If the menu does not show up right away:

```sh
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```

(Then refresh the LuCI page / clear cache.)

## Usage notes

- After enabling FakeHTTP/FakeSIP and clicking *Save & Apply*, the service starts
  automatically. The settings page shows a **Service status** line (Running/Stopped);
  reload the page to refresh it.
- On slow PPPoE links, if a service does not come up at the very first boot (because
  the WAN interface was not ready yet), just open its page and click *Save & Apply*
  once — or reboot — and it will start.
- To check system-wide logs: **Status -> System Log** (or `logread`). Per-service run
  logs are on each tool's page (see **Logging** above).

## Uninstall behaviour

Removing the package stops and disables all three services, removes the log-cleanup
cron entry, and deletes the `/tmp` log files. It does **not** touch shared system
components — in particular it never removes `nftables`/the firewall backend and never
disables the cron service.

## Files preserved during sysupgrade

```text
/etc/config/taoistfuchen
/etc/config/fakehttp
/etc/config/fakesip
/etc/taoistfuchen/
```

## Licenses

- This LuCI app: **MIT**.
- Bundled `fakehttp` and `fakesip` binaries: **GPLv3**, © MikeWang000000.
  - https://github.com/MikeWang000000/FakeHTTP
  - https://github.com/MikeWang000000/FakeSIP
