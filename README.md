# Taoist Fuchen 2.1.0

面向 OpenWrt 25.12.5 的 LuCI 工具包，在 **服务 → Taoist Fuchen** 下提供：

1. Custom Logo：替换 LuCI 页面 Logo 与浏览器 favicon；
2. FakeHTTP：在路由器 WAN 侧配置 FakeHTTP 0.9.18；
3. FakeSIP：在路由器 WAN 侧配置项目自维护的 FakeSIP 0.9.4。

FakeHTTP 是经过校验的静态 AArch64 ELF；FakeSIP 0.9.4 则由 OpenWrt SDK 从仓库内完整
源码交叉编译，并动态使用 OpenWrt 的 `libnetfilter-queue`。因为 APK 仍包含 AArch64
FakeHTTP，软件包架构固定为 `aarch64_cortex-a53`，适用于 Linksys E8450 / Belkin RT3200
等匹配目标，不能作为 `all` 架构包装到 x86、MIPS 或其他设备上。

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

## FakeSIP 0.9.4

本包自维护的 0.9.4 基于 Droid-MAX/FakeSIP commit
`bb6fdd88e7fa6f6d4fb1b02e359e5e68c7d778b6`（0.9.3 Release 的源码），保留该分支新增的
`-p` 端口白名单和 `-P` 端口黑名单。完整源码位于
`luci-app-taoistfuchen/src/fakesip/`，Actions 会使用固定 OpenWrt SDK 编译，不再从仓库复制
预编译 FakeSIP ELF。

0.9.4 修正了基线源码中的以下问题：

- IPv6 nft 表使用错误的 IPv4 `icmp` 表达式，现改为
  `icmpv6 type time-exceeded`；
- IPv6 nft batch 被重复提交，现只加载一次；
- IPv4/IPv6 伪造 UDP 包的 length 字段没有包含 UDP 头，且 IPv6 值未转为网络字节序；
- 双栈规则安装一半失败时，现会清理已经创建的规则；
- ICMP Time Exceeded 丢弃规则现限定到所选入站设备，不再越过接口选择全局生效；
- 取消出站原 UDP 的 raw socket 重发；伪包发送后直接放行原 NFQUEUE skb，既避免重复又保留
  checksum、mark、priority 等内核元数据；
- SIGTERM/SIGINT 退出标志改为信号安全类型，便于 procd 正常停止服务。

FakeSIP 为 UDP 会话前期生成低 TTL SIP 诱饵包，原始 UDP 仍被放行。页面提供：

- 一个或多个实际 WAN 设备；
- 兼容双向、仅出站或仅入站，新装默认仅出站（补偿上游标志反置后显式 `-0`）；
- IPv4、IPv6 或双栈，新装默认 IPv4+IPv6 双栈；升级时保留所有已有合法选择；
- 端口黑名单、白名单或全部端口，默认 `-P 53` 以避免 DNS 延迟；
- 自动 SIP URI 或一个受校验的自定义 `sip:` URI；
- repeat、TTL、动态 TTL、流量日志、NFQUEUE、fwmark 与 mask。

基线版本对 `PACKET_HOST`/`PACKET_OUTGOING` 的单向标志检查相反；0.9.4 保持该上游行为，
init 脚本会在仅入站、仅出站模式下交换对应 CLI 标志，使页面方向仍按路由器真实流向显示。
默认命令等价于：

```sh
fakesip -0 -4 -6 -i <WAN设备> \
  -P 53 -s \
  -r 2 -t 3 -n 8971 -m 0x10000 -x 0x10000
```

IPv6 WAN 必须已经具备可用的全局 IPv6 连接；0.9.4 暂不解析 IPv6 扩展头，因此只有 UDP
直接跟在 IPv6 基本头后的包会生成诱饵。用户仍可在页面中选择仅 IPv4、仅 IPv6、仅入站
或双向；软件升级不会覆盖任何已有的合法方向和地址族设置。

FakeSIP 会在所选入站设备上丢弃对应的 ICMP time-exceeded，因而该设备上的 traceroute
仍可能受影响；其他接口不再被这条规则波及。关闭服务时，init 脚本会兜底删除
`table ip fakesip` 与 `table ip6 fakesip`。

## 服务生命周期与日志

- 两个服务始终向 procd 注册 UCI reload trigger，即使功能当前关闭；
- 不再创建 boot marker，也不再启动脱离 procd 的后台 `sleep`；
- WAN ifup/ifdown 事件只触发受锁保护的 init reload；
- procd 采用受限 respawn，并直接将 stdout/stderr 写入 OpenWrt `logd`；
- LuCI 日志面板读取系统 ring buffer，不再创建可能写满 RAM 的 `/tmp/*.log`；
- start/reload 会先清理遗留规则，stop 与卸载会兜底删除本工具自己的 nft 表。

## 依赖

软件包只在 APK 元数据中显式声明以下运行时依赖，不会把这些外部包嵌入本插件 APK：

- `luci-base`；
- `cgi-io`；
- `nftables`；
- `kmod-nft-queue`；
- `coreutils-stat` 与 `coreutils-od`（用于服务端目录和图片结构校验）；
- `libnetfilter-queue1`（Makefile 中的源码包名为 `libnetfilter-queue`；其余库依赖由 `apk`
  递归下载）。

在 OpenWrt 25.12.5 上安装本插件 APK 时，`apk` 会从设备已经配置的软件源自动下载尚未
安装的直接和递归依赖。例如 `kmod-nft-core` 由 `kmod-nft-queue` 递归拉取，不需要在本
项目中重复声明或随 Actions 产物提供。

如果 `kmod-nft-queue` 因 kernel 版本不匹配而无法安装，需要修正 OpenWrt 25.12.5 软件源，
或在固件中内置匹配的 `CONFIG_PACKAGE_kmod-nft-queue=y`。

## 构建

### 通过 GitHub 网页上传并编译

1. 解压源码包，进入解压后生成的外层目录；不要把 ZIP 文件本身上传到仓库。
2. 将该目录**内部的全部文件和文件夹**上传到 GitHub repository 的仓库根目录。
3. 确认以下三个路径直接位于仓库根，而不是又套在一层同名目录中：

   ```text
   .github/workflows/build.yml
   luci-app-taoistfuchen/
   README.md
   ```

   `.github` 是隐藏目录，上传时必须确认它也在文件列表中；否则 GitHub 不会发现 Actions
   workflow。更详细的操作见 [GITHUB_WEB_UPLOAD.md](GITHUB_WEB_UPLOAD.md)。

4. 提交上传后，进入仓库的 **Actions → Build OpenWrt Package**。push 会自动触发，也可
   使用 **Run workflow** 手动触发。
5. 编译完成后，在该次 run 的 **Artifacts** 下载
   `luci-app-taoistfuchen-25.12.5-mediatek-mt7622`。

Actions 固定使用 OpenWrt 25.12.5 `mediatek/mt7622` 官方 SDK 和 SHA-256。SDK 编译过程中
可能在临时工作目录生成依赖 APK，这是 OpenWrt 构建系统解析依赖的正常行为；上传的
artifact 会强制校验为**恰好一个** `luci-app-taoistfuchen-*.apk`，不会包含 `kmod-*`、
`nftables-*`、`coreutils-*` 或 `libnetfilter-*` 依赖 APK。许可证、来源说明和两份 GPL
对应源码归档会一同
保留，它们不是安装依赖。

### 手工使用 SDK 构建

不要只运行裸 `make defconfig`：官方 SDK 的 `Config-build.in` 会默认选中一千多个无关包。
仓库脚本会先中和这些 SDK 默认项，再保留当前固定 SDK 打包 nft kmod 所需的 provider
closure：

```sh
cp -a luci-app-taoistfuchen openwrt-sdk/package/
(
  cd openwrt-sdk
  ./scripts/feeds update -a
  ./scripts/feeds install -a
)
sh scripts/configure-openwrt-sdk.sh openwrt-sdk
make -C openwrt-sdk package/luci-app-taoistfuchen/compile V=s
sh scripts/prepare-artifact.sh openwrt-sdk output_pkg
```

### 安装主 APK

只需把 artifact 中的主 APK 复制到路由器 `/tmp`，然后执行：

```sh
apk update
apk add --allow-untrusted /tmp/luci-app-taoistfuchen-*.apk
```

`apk` 会自动下载未安装的外部依赖。这个过程要求目标系统的软件源、架构和内核 ABI 与
官方 OpenWrt 25.12.5 `mediatek/mt7622` 匹配；使用自编译内核的固件即使显示相同版本号，
也可能因 kernel hash 不同而拒绝官方 kmod。

源码仓库的 host 侧回归检查：

```sh
sh scripts/normalize-source-permissions.sh
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
- FakeHTTP 二进制与 FakeSIP 0.9.4 源码：GNU GPLv3；
- 精确版本、commit、Release 资产 SHA-256、对应源代码归档与重建说明：
  [THIRD_PARTY_SOURCES.md](THIRD_PARTY_SOURCES.md)。
