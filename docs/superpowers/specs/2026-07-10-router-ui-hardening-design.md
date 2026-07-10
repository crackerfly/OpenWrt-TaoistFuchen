# Taoist Fuchen 路由器场景重构设计

## 范围

本次基于 OpenWrt 25.12.5 重构三个功能，并修复上一轮审查中除
`firmware-openwrt-config.txt` 之外的发布前高优先级问题。该文件必须保持原样。

## FakeHTTP

- 固定使用随包提供的 FakeHTTP 0.9.18。
- 默认仅处理出站连接（显式 `-1`），默认同时处理 IPv4/IPv6。
- 支持多个实际 WAN 设备；高级模式可选择所有接口。
- 伪装载荷改为可排序表格，支持 HTTP Host、HTTPS SNI 和受限二进制载荷。
- 所有载荷按表格顺序全局轮换；保留重复条目，以支持权重。
- 默认载荷为 HTTP `www.speedtest.net`。
- 高级项包括 repeat、TTL、动态 TTL、详细流量日志、NFQUEUE、fwmark/mask。
- 不向用户开放 daemon、kill、skip-firewall、iptables 和任意日志路径。

## FakeSIP

- 固定使用 Droid-MAX/FakeSIP 0.9.3 arm64 Release，保留其端口白名单/黑名单能力。
- 默认显式处理双向（`-0 -1`），以规避该版本方向检查语义错位。
- 仅入站/仅出站时由 init 交换上游反置的单向标志，保持页面语义正确。
- 默认强制 IPv4（`-4`）；0.9.3 的 nft IPv6 规则存在已确认缺陷，不在本版本开放。
- 默认使用端口黑名单并排除 DNS 53；可切换白名单或全部端口。
- 默认生成自动 SIP URI；高级用户可填写一个受校验的 `sip:` URI。
- 公开 repeat、TTL、动态 TTL、流量日志、NFQUEUE、fwmark/mask。
- 不公开所有接口、任意二进制负载、daemon、skip-firewall、iptables 和日志路径。

## 服务生命周期和日志

- 删除后台 `sleep` 启动和 boot marker；init 脚本始终注册 procd 配置触发器。
- WAN ifup/ifdown 通过 hotplug 触发服务 reload，不创建脱离 procd 的后台任务。
- 关闭、卸载及下一次启动/重载时兜底删除本服务的 IPv4/IPv6 nft 表。
- 使用 procd stdout/stderr 写入 OpenWrt logd，不创建无限增长的 `/tmp` 日志文件，
  不再安装 cron 日志清理任务。
- LuCI 日志面板只读取 logd 中对应服务的最近记录。

## Custom Logo

- 附件 SVG 作为受信任内置资源安装到
  `/usr/share/taoistfuchen/assets/default-logo.svg`，首次安装复制至
  `/etc/taoistfuchen/assets/default-logo.svg`。
- 功能默认仍关闭；开启后若未另选文件，页面 Logo 和 favicon 都使用内置 SVG。
- 用户上传仅开放 PNG Logo，以及 PNG/ICO favicon。用户 SVG 不开放上传，避免同源 SVG
  主动内容风险；内置 SVG 通过包内容校验信任。
- 专用 CGI 在读取请求体前检查 `Content-Length`，上传到 0700 staging 目录，验证大小、
  扩展名和 magic 后原子移动；单文件 512 KiB，总目录配额 4 MiB。
- FakeHTTP 二进制载荷通过同一专用端点上传，限制为 `.bin` 且 1–1200 字节。

## 主题适配

- 不再覆盖主题自带 Logo，也不创建或恢复永久 `.backup`。
- 运行时资源放在 `/www/luci-static/taoistfuchen/customlogo/`。
- 对 Bootstrap、Argon 2.4.3、Fluent 的实际 header/login 模板插入带 START/END
  标记的 CSS/JS 引用；禁用时只移除标记块和包自有运行时资源。
- Bootstrap 通过 CSS 给 hostname brand 添加图形；favicon 由运行时 JS 替换。
- Argon 仅在检测到 2.4.3 时适配，兼容其 Lua/ucode 模板路径；导航用 CSS，登录图标用 JS。
- Fluent 顶栏和登录图标由 JS 精确替换，不修改“关于”页 Logo。
- 主题升级覆盖模板时最多暂时失去定制，不允许旧备份回滚新主题文件。

## 安全与打包

- 所有接口、host、SIP URI、端口、数值、资源路径在 LuCI 和 init 两层校验。
- 包架构显式设为 `aarch64_cortex-a53`。
- 显式依赖 `nftables`、`kmod-nft-queue` 和 `cgi-io`。
- 分离 Custom Logo、FakeHTTP、FakeSIP 三组 ACL。
- 记录两份二进制的版本、来源、提交和 SHA-256，并附对应源代码归档。
- 包版本升级为 2.0.0。
