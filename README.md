# Taoist Fuchen 2.0.0

面向 OpenWrt 25.12.5 的 LuCI 工具包，在 **服务 → Taoist Fuchen** 下提供：

1. Custom Logo：替换 LuCI 页面 Logo 与浏览器 favicon；
2. FakeHTTP：在路由器 WAN 侧配置 FakeHTTP 0.9.18；
3. FakeSIP：在路由器 WAN 侧配置 Droid-MAX/FakeSIP 0.9.3。

本仓库内置的两个网络工具均为静态 AArch64 ELF，因此软件包架构固定为
`aarch64_cortex-a53`，适用于 Linksys E8450 / Belkin RT3200 等匹配目标，不能作为
`all` 架构包装到 x86、MIPS 或其他设备上。

## Custom Logo

随包内置一个经过检查的 `default-logo.svg`。功能默认关闭，但 Logo 与 favicon 的默认
选择均已指向该文件，因此第一次开启后无需额外上传即可生效。

支持的主题：

- OpenWrt 官方 Bootstrap；
- luci-theme-argon **2.4.3**（仅适配该版本）；
- [luci-theme-fluent](https://github.com/LazuliKao/luci-theme-fluent)。

2.0 不再覆盖主题包拥有的 Logo 文件，也不再用永久 `.backup` 恢复主题。服务只在主题
header/login 模板中加入可识别的引用标记，运行时文件全部位于：

```text
/www/luci-static/taoistfuchen/customlogo/
```

关闭功能或卸载软件包时，只删除这些标记和包自有运行时文件。主题升级最多会暂时移除
自定义效果，不会被旧备份回滚。

### 上传限制

- 页面 Logo：用户可上传 PNG，最大 512 KiB，最大边长 2048；
- favicon：用户可上传 PNG 或 ICO，最大 512 KiB；
- SVG：只允许随包提供的受信任内置 SVG，不开放任意同源 SVG 上传；
- 总资源目录配额：4 MiB。

专用 CGI 在读取上传主体前检查大小，并在 0700 staging 目录完成 magic、尺寸与路径校验，
验证成功后再原子移动。通用 LuCI `cgi-upload` 不会直接写最终资源目录。

## FakeHTTP 0.9.18

FakeHTTP 在 TCP 会话前期生成低 TTL 伪装载荷，用于干扰自动 DPI 分类。它不是代理、隧道
或加密工具，不会隐藏真实目标，也不保证对人工抓包分析有效。

路由器页面提供：

- 一个或多个实际 WAN 设备，或高级“所有接口”模式；
- 出站、入站或双向连接，默认显式 `-1`（仅出站）；
- IPv4、IPv6 或双栈，默认双栈；
- 可排序的伪装载荷表：HTTP Host、HTTPS SNI、二进制 TCP payload；
- repeat、TTL、动态 TTL、流量日志、NFQUEUE、fwmark 与 mask。

多个 `-h`、`-e`、`-b` 条目按表格中的全局顺序循环使用，不是随机选择。重复条目不会去重，
因此可通过重复条目表达权重。例如 A、B、B 的长期比例约为 1:2。该行为来自官方
[Issue #78](https://github.com/MikeWang000000/FakeHTTP/issues/78)。0.9.18 内部以逆序构建
payload 环，init 脚本会反向传参，使实际轮换顺序与页面表格一致。

默认命令等价于：

```sh
fakehttp -1 -4 -6 -i <WAN设备> \
  -h www.speedtest.net -s \
  -r 2 -t 3 -n 8970 -m 0x8000 -x 0x8000
```

二进制 payload 只能从 `/etc/taoistfuchen/fakehttp-payloads/` 选择，大小限制为
1–1200 字节。

## FakeSIP 0.9.3

本包使用 [Droid-MAX/FakeSIP 0.9.3](https://github.com/Droid-MAX/FakeSIP/releases/tag/0.9.3)
arm64 Release，而不是 MikeWang 原仓库的 0.9.1 二进制。该分支增加 `-p` 端口白名单和
`-P` 端口黑名单。

FakeSIP 为 UDP 会话前期生成低 TTL SIP 诱饵包，原始 UDP 仍被放行。页面提供：

- 一个或多个实际 WAN 设备；
- 兼容双向、仅出站或仅入站，默认显式 `-0 -1`；
- 端口黑名单、白名单或全部端口，默认 `-P 53` 以避免 DNS 延迟；
- 自动 SIP URI 或一个受校验的自定义 `sip:` URI；
- repeat、TTL、动态 TTL、流量日志、NFQUEUE、fwmark 与 mask。

0.9.3 的 nft IPv6 规则仍存在上游缺陷，本包当前强制使用 IPv4，不在页面提供 IPv6 开关。
该版本对 `PACKET_HOST`/`PACKET_OUTGOING` 的单向标志检查也相反；init 脚本已在仅入站、
仅出站模式下交换对应 CLI 标志，页面方向仍按路由器真实流向显示。
默认命令等价于：

```sh
fakesip -0 -1 -4 -i <WAN设备> \
  -P 53 -s \
  -r 2 -t 3 -n 8971 -m 0x10000 -x 0x10000
```

FakeSIP 自身创建的 nft 规则会处理 ICMP time-exceeded，可能影响 traceroute；关闭服务时
init 脚本会兜底删除 `table ip fakesip` 与 `table ip6 fakesip`。

## 服务生命周期与日志

- 两个服务始终向 procd 注册 UCI reload trigger，即使功能当前关闭；
- 不再创建 boot marker，也不再启动脱离 procd 的后台 `sleep`；
- WAN ifup/ifdown 事件只触发受锁保护的 init reload；
- procd 采用受限 respawn，并直接将 stdout/stderr 写入 OpenWrt `logd`；
- LuCI 日志面板读取系统 ring buffer，不再创建可能写满 RAM 的 `/tmp/*.log`；
- start/reload 会先清理遗留规则，stop 与卸载会兜底删除本工具自己的 nft 表。

## 依赖

软件包显式依赖：

- `luci-base`；
- `cgi-io`；
- `nftables`；
- `kmod-nft-queue`；
- `coreutils-stat` 与 `coreutils-od`（用于服务端目录和图片结构校验）。

如果 `kmod-nft-queue` 因 kernel 版本不匹配而无法安装，需要修正 OpenWrt 25.12.5 软件源，
或在固件中内置匹配的 `CONFIG_PACKAGE_kmod-nft-queue=y`。

## 构建

GitHub Actions 使用 OpenWrt 25.12.5 `mediatek/mt7622` SDK：

```sh
cp -a luci-app-taoistfuchen openwrt-sdk/package/
cd openwrt-sdk
./scripts/feeds update -a
./scripts/feeds install -a
make defconfig
make package/luci-app-taoistfuchen/compile V=s
```

安装生成的 APK：

```sh
apk add --allow-untrusted luci-app-taoistfuchen-*.apk
```

源码仓库的 host 侧回归检查：

```sh
./tests/run.sh
sha256sum -c third_party/SHA256SUMS
```

## 配置保留与卸载

sysupgrade 保留：

```text
/etc/config/taoistfuchen
/etc/config/fakehttp
/etc/config/fakesip
/etc/taoistfuchen/
```

卸载会停止并禁用三个服务，移除模板注入、运行时资源、staging 文件、旧版 cron 行及本工具
创建的 nft 表；不会删除共享的 nftables、cron 或其他系统组件。

## 许可与对应源代码

- LuCI 应用代码：MIT；
- FakeHTTP/FakeSIP 二进制：GNU GPLv3；
- 精确版本、commit、Release 资产 SHA-256、对应源代码归档与重建说明：
  [THIRD_PARTY_SOURCES.md](THIRD_PARTY_SOURCES.md)。
