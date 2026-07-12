# TaoistFuchen 2.1.0-r3 开机延迟、WAN 生命周期与 FakeSIP 0.9.5 日志修复设计

## 目标

在不改变 FakeHTTP/FakeSIP 实际数据包处理语义的前提下，完成以下三项关联修复：

1. 在两个 LuCI 设置页恢复仅针对系统开机自动启动的可配置延迟；
2. 将 WAN 热插拔从统一 `reload` 改造成明确的 `boot`、`ifdown`、`ifup` 生命周期；
3. 修正 FakeSIP 方向和双栈启动日志，使显示内容与实际处理行为一致。

主插件版本提升为 `2.1.0-r3`。日志修复后的 TaoistFuchen 维护版 FakeSIP 提升为
`0.9.5`，避免已经发布的 `0.9.4` 出现同版本、不同源码和不同 SHA-256。

## 已确认的现状与根因

### 开机延迟缺失

- `fakehttp` 和 `fakesip` 的 UCI 默认配置中没有 `boot_delay`；
- `99_taoistfuchen` 会主动删除两个历史 `boot_delay` 选项；
- 两个 init 脚本没有开机等待路径；
- WAN 在开机约 11 秒时发生 `ifup`，当前 hotplug 直接执行 `reload`，因此即使单独补上
  `boot()`，也可能被这个 `reload` 提前绕过；
- 旧版脱离 procd 的 `(sleep; init start) &` 方案不可恢复，因为它难以在 stop、reload、
  卸载和 WAN 重拨时可靠取消。

### WAN 重拨竞态

当前 `99-taoistfuchen` 对匹配的 `ifdown` 和 `ifup` 执行同一条 `reload`。因此断线时会
一边清理旧设备，一边重新进入接口存在性验证和启动流程。FakeHTTP 与 FakeSIP 对
`pppoe-wan` 消失时点的取样不同，导致一个验证失败、另一个在 PPP 重建期间提前启动。

### FakeSIP 日志方向错误

FakeSIP 继承了上游遗留的反向变量名称：

| 参数 | 遗留变量 | 实际 NFQUEUE 路径 | 实际语义 |
| --- | --- | --- | --- |
| `-0` | `g_ctx.inbound` | `PACKET_OUTGOING` | 仅出站 |
| `-1` | `g_ctx.outbound` | `PACKET_HOST` | 仅入站 |
| `-0 -1` | 两者均启用 | 两条路径 | 入站和出站 |

当前 init 脚本的 `outbound -> -0`、`inbound -> -1` 映射与实际行为一致。错误只出现在
`mainfun.c` 和 FakeSIP README 按遗留变量名生成的帮助与启动日志。双栈没有显示，是因为
双栈分支将地址族说明设置成了空字符串。

## 选定架构

采用“独立 procd 开机调度器 + 每服务生命周期状态”的方案，不在主进程前同步 sleep，
也不创建脱离 procd 的后台任务。

### 组件边界

1. **FakeHTTP/FakeSIP init 服务**
   - 继续负责配置校验、命令参数、procd 主实例、respawn 和 nft 清理；
   - 根据调用上下文区分人工操作、开机调度、`ifdown` 和 `ifup`；
   - 人工 `start/restart/reload` 永远不应用开机延迟。

2. **内部开机延迟调度器**
   - 作为独立 init/procd 服务运行；
   - 为 FakeSIP 和 FakeHTTP 建立两个独立一次性等待实例，使 40 秒和 60 秒并行计算；
   - 以 `/proc/uptime` 为时间基准，目标时间分别是系统启动后配置的秒数，而不是两个脚本
     串行执行后的累计时间；
   - 到期后调用目标服务的正常启动入口，由目标服务在当时执行接口与完整配置校验；
   - 不启用 respawn，等待任务退出后不会再次计时。

3. **root-only 运行时状态**
   - 状态放在 `/var/run` 下由 root 管理的专用目录，不使用可被普通用户替换的裸 `/tmp`
     文件；
   - 每个服务拥有独立、带 token 的等待状态；
   - 每个服务同时维护独立的链路 `phase/generation`，并使用 root-only
     生命周期锁串行化调度器、人工操作、热插拔和到期 runner 的状态转换；
   - 人工操作、禁用、stop、卸载会使 token 失效，并取消对应 procd 等待实例；
   - 等待器自身不得把状态改成完成；它只调用目标 init 的内部到期入口，由目标 init 在
     procd 锁和生命周期锁内原子复核 token、禁用状态及最新链路 phase，失效任务不得产生
     迟到启动。

4. **WAN hotplug 状态机**
   - `ifdown` 和 `ifup` 使用不同入口，不再共用普通 `reload`；
   - 只处理已启用且与所选实际 Linux 设备匹配的服务；
   - FakeHTTP 的 `interface_mode=all` 保留其全部设备语义；
   - 优先使用 hotplug 的 `DEVICE`；如果 `DEVICE` 缺失且无法从事件上下文解析出实际设备，
     不得猜测目标、不得启动或重启无关服务，只记录诊断日志并等待下一次具有明确设备的事件；
   - 成功 `ifup` 时把 `INTERFACE → 已验证 L3 device` 原子缓存到上述 root-only 运行目录；
     `ifdown` 缺失 `DEVICE` 时先解析实时 L3 device，失败后只可使用同一 `INTERFACE` 的缓存，
     不得退回 `.device` 指向的 PPPoE 底层物理口；
   - 取得目标服务锁后必须重新加载 enabled、interface mode 和 device 列表；等待锁期间已被
     Save & Apply 移除的旧设备事件必须完全 no-op；
   - hotplug 脚本自身不执行 sleep。

## 配置与 LuCI

两个页面都在 Enable 选项之后增加 `boot_delay`：

| 服务 | 新装及 r3 一次性升级值 | 合法范围 |
| --- | ---: | ---: |
| FakeSIP | 40 秒 | 0–600 秒 |
| FakeHTTP | 60 秒 | 0–600 秒 |

字段为必填规范十进制整数。接受 `0` 和 `600`；拒绝空值、负数、小数、带符号值、前导零
形式以及大于 600 的值。`0` 表示系统开机时也立即启动。

页面说明必须明确：该值只影响路由器开机时已经启用服务的自动启动；在页面启用、禁用或
Save & Apply 会立即应用，不等待该时间。

init 的开机路径仍需防御性校验直接编辑 UCI 产生的非法值。非法值分别回退到 FakeSIP 40
秒和 FakeHTTP 60 秒；人工启动路径不应因为 `boot_delay` 非法而延迟或拒绝启动。

## r3 升级语义

采用用户确认的方案 B：第一次安装或升级到 r3 时，无条件将 FakeSIP 设置为 40 秒、
FakeHTTP 设置为 60 秒，覆盖旧版仍存在的合法或自定义值。

迁移同时写入 r3 专用完成标记。相同 r3 被重新安装时，如果该标记已经存在，不得再次覆盖
用户在 r3 中修改过的延迟值。后续版本也不得把此一次性迁移当成永久归一化规则。

`uci-defaults` 对两个服务的启动调用必须标记为“自动启动上下文”：

- 在线安装且系统 uptime 已超过延迟目标时，服务立即启动；
- 首次开机或 sysupgrade 恢复阶段仍位于延迟窗口内时，进入调度器等待；
- 不得把 `uci-defaults` 的普通 `start` 误判为用户人工启动。

## 生命周期状态机

| 事件 | 预期行为 |
| --- | --- |
| `boot`，服务关闭 | 不创建主实例或等待任务，但保留配置 reload trigger |
| `boot`，延迟为 0 | 立即进入正常启动与接口校验 |
| `boot`，延迟大于 0 | 注册等待状态，不提前验证尚未创建的 PPPoE 设备 |
| 开机窗口内目标设备 `ifup` | 记录/保留就绪状态，不启动、不覆盖等待任务 |
| 延迟到期且设备存在 | 进入正常启动路径并创建主 procd 实例 |
| 延迟到期但设备不存在 | 正常验证失败并保持停止；之后目标设备 `ifup` 再启动 |
| 人工 Enable + Save & Apply | 取消等待，立即进入正常启动路径 |
| 人工 Disable + Save & Apply | 取消等待、停止实例、清理本服务 nft 表 |
| 人工 `start/restart/reload` | 不读取开机延迟，立即执行 |
| 目标设备 `ifdown` | 先记录 link down 使到期任务失效，再终止主实例，进程终止后清理所属 nft 表，并提交保留 trigger 的空定义；不执行接口验证，不尝试重启 |
| 开机窗口结束后的目标设备 `ifup` | 设备存在后立即启动/重新提交定义，不增加固定重拨延迟 |
| 主进程异常退出 | 使用现有 procd respawn，不能再次套用开机延迟 |
| 卸载 | 停止主服务和内部调度器，取消所有等待状态并清理所属 nft 表 |

人工“立即执行”只表示不受 `boot_delay` 限制；如果用户要求启动时目标接口确实不存在，原有
接口校验仍可返回失败，不能为了人工立即性而绕过安全校验。

## FakeSIP 0.9.5 日志修复

本次只修改表达层，不修改 NFQUEUE 分类、rawsend 门控或 init 参数映射：

- usage 和 FakeSIP README 改为 `-0 process outbound packets`、
  `-1 process inbound packets`；
- 启动日志显式输出 `outbound only`、`inbound only` 或
  `inbound and outbound`；
- 地址族显式输出 `IPv4 only`、`IPv6 only` 或 `IPv4 and IPv6`；
- 给遗留反向变量增加注释，本次不进行跨文件机械重命名；
- `outbound -> -0`、`inbound -> -1`、`both -> -0 -1` 保持不变；
- 缺省未传方向参数时仍保持双向处理。

由于维护源码发生变化，版本提升至 `0.9.5`，并重新生成
`FakeSIP-TaoistFuchen-0.9.5.tar.gz`、来源校验值和 APK 内版本验证规则。

## 错误处理与安全约束

- 等待时间必须在 LuCI、迁移脚本和运行时三层校验；
- 等待任务必须受 procd 管理、可停止且不可脱管；
- 状态文件必须防止路径注入、符号链接替换和过期 token 复用；
- 显式 stop/restart 必须在 rc.common 执行 `procd_kill` 之前使等待 token 失效；runner 不得在
  stop 与 `service_stopped()` 之间把服务复活；
- 所有目标实例的提交、`link_down`、`link_up` 和 `boot_expired` 必须由该 init 的 procd 锁
  串行化；所有状态转换还必须取得同一服务的生命周期锁；
- rc_procd 已打开 service JSON 后若需要删除旧实例，只能在子 shell 中调用
  `( procd_kill ... )`，隔离其 `json_init/json_cleanup`；nft cleanup 必须在该 kill 返回后执行；
- `boot_expired` 必须在调用嵌套 `start` 前持锁预检精确 wait token，避免 stale runner 提交
  空定义并停掉人工启动的实例；
- 重复 `ifup`、重复人工 Apply 和定时器同时到期必须是幂等的，最终最多保留一个主实例；
- `ifdown` 不能调用会进入启动验证的普通 `reload`；
- 开机窗口内的 `ifup` 不得把 40/60 秒缩短为网络约 11 秒上线时间；
- nft 清理仍只删除本插件自己的 `fakehttp` 和 `fakesip` 表；
- 不改变 FakeSIP 数据包方向、NFQUEUE、fwmark、IPv4/IPv6 处理或动态库依赖。

## 测试与发布门禁

实施必须采用测试驱动顺序，先添加能够复现当前错误的失败测试，再修改生产代码。

1. **配置与迁移**
   - 新装默认值 40/60；
   - `0`、`600` 和所有非法边界；
   - r3 首次升级强制覆盖旧值；
   - r3 完成标记存在时重装不二次覆盖。

2. **开机调度**
   - 两个等待并行而非累计 100 秒；
   - uptime 已超过目标时立即启动；
   - 延迟为 0、服务关闭、接口未创建、接口在等待期间上线；
   - 人工启动、禁用、stop 和卸载能够取消迟到任务；
   - 主进程 respawn 不重新等待。

3. **hotplug**
   - `ifdown` 只停止和清理；
   - `ifup` 在开机窗口内不启动；
   - 窗口结束后只在匹配设备存在时启动；
   - PPPoE 重拨序列不会在重建中途拉起 FakeSIP；
   - 缺失 `DEVICE` 的事件采取保守处理，不得误启无关服务。

4. **FakeSIP 日志**
   - 三种方向和三种地址族的 usage/启动日志；
   - init 参数映射、`mainfun.c` 变量赋值和 `rawsend.c` 门控保持不变；
   - 源码目录与 0.9.5 对应源码归档逐文件一致；
   - clang-format 全量检查通过。

5. **构建与产物**
   - 完整仓库回归测试与源码 ZIP 解压复测；
   - OpenWrt 25.12.5 `mediatek/mt7622` 官方 SDK 构建；
   - APK 版本为 `2.1.0-r3`；
   - APK 内 `/usr/bin/fakesip` 为 0755 AArch64 ELF，版本为 0.9.5；
   - APK 内包含正确方向和 `IPv4 and IPv6` 日志字符串；
   - 动态库依赖、源码来源、SHA-256 和只上传主 APK 的 Actions 规则保持通过。

## 不在本次范围内

- 不重命名 FakeSIP 的遗留内部方向变量；
- 不修改 FakeHTTP/FakeSIP 的包处理算法、NFQUEUE 规则或默认流量方向；
- 不增加 WAN 重拨后的任意固定等待时间；确认目标设备 `ifup` 后立即恢复；
- 不调整 Custom Logo、私有固件配置或其他无关功能。

本设计取代 `2026-07-10-router-ui-hardening-design.md` 中“完全移除开机等待”的历史决定，
但保留其核心安全约束：禁止脱离 procd 的后台 sleep、禁止不可取消的迟到启动。
