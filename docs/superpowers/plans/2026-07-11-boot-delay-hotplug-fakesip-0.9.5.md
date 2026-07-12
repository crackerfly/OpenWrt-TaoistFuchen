# TaoistFuchen 2.1.0-r3 Boot Delay, WAN Lifecycle, and FakeSIP 0.9.5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 发布 TaoistFuchen `2.1.0-r3`，实现只作用于系统开机自动启动的 FakeSIP 40 秒/FakeHTTP 60 秒延迟，消除 PPPoE `ifdown`/`ifup` 竞态，并以 FakeSIP `0.9.5` 修正方向和双栈日志。

**Architecture:** 新增独立的 procd 一次性开机调度器，在 `/var/run` 的 root-only 状态目录中维护每服务 token、目标 uptime、链路 phase/generation 和生命周期锁。所有可能启动或停止目标实例的路径都由目标 init 的 procd 锁串行化；调度器只在同一生命周期锁内布置等待状态，runner 不自行宣告完成，而是调用目标 init 的原子 `boot_expired` 入口。FakeHTTP/FakeSIP init 继续独占主进程配置与验证，并通过明确的 `boot`、`auto`、`link_down`、`link_up`、`boot_expired`、`manual` 入口决定是等待、停止还是立即启动。FakeSIP 只修改帮助和启动日志表达层，不修改 NFQUEUE/rawsend 实际方向门控。

**Tech Stack:** OpenWrt 25.12.5、BusyBox ash、procd/rc.common、UCI、LuCI JavaScript、Python/shell/Node 回归测试、C99、clang-format 18、OpenWrt `mediatek/mt7622` SDK、APK v3。

## Global Constraints

- 主包版本必须是 `2.1.0-r3`。
- TaoistFuchen 维护版 FakeSIP 必须是 `0.9.5`。
- FakeSIP 新装/首次 r3 迁移延迟必须是 `40` 秒；FakeHTTP 必须是 `60` 秒。
- `boot_delay` 只接受规范十进制整数 `0–600`；`0` 表示开机不延迟。
- 按已确认方案 B，首次安装/升级 r3 必须覆盖旧延迟；同一 r3 重装不得再次覆盖用户新值。
- LuCI Enable/Disable + Save & Apply 和 CLI `start/restart/reload` 必须立即执行，不受延迟影响。
- `ifdown` 只能停止主实例并清理本服务 nft 表；`ifup` 只能在明确匹配且设备存在时恢复。
- 开机等待窗口内的 `ifup` 不得把启动提前到 WAN 约 11 秒上线时。
- 两个延迟必须并行，不能串行累计成约 100 秒。
- 不允许 `(sleep; start) &`、裸 `/tmp/*.bootwait` 或其他脱离 procd 的后台等待。
- 主进程 respawn 不得再次应用开机延迟。
- FakeSIP 保持 `outbound -> -0`、`inbound -> -1`、`both -> -0 -1`。
- 不修改 FakeSIP `nfqueue.c`、`rawsend.c` 的方向门控、NFQUEUE、fwmark、nft 规则或动态库依赖。
- 不修改 `firmware-openwrt-config.txt`；其 SHA-256 必须保持现有 release 测试值。
- 历史设计/计划中的旧版本号保持历史记录，不做全仓机械替换。

---

### Task 1: LuCI 字段、新装默认值和方案 B 一次性迁移

**Files:**
- Create: `tests/test_luci_boot_delay.js`
- Modify: `tests/run.sh`
- Modify: `tests/test_release.py`
- Modify: `tests/test_migration.sh`
- Modify: `luci-app-taoistfuchen/htdocs/luci-static/resources/view/taoistfuchen/fakesip.js`
- Modify: `luci-app-taoistfuchen/htdocs/luci-static/resources/view/taoistfuchen/fakehttp.js`
- Modify: `luci-app-taoistfuchen/root/etc/config/fakesip`
- Modify: `luci-app-taoistfuchen/root/etc/config/fakehttp`
- Modify: `luci-app-taoistfuchen/root/etc/uci-defaults/99_taoistfuchen`
- Modify: `luci-app-taoistfuchen/Makefile`

**Interfaces:**
- Produces: UCI `fakesip.main.boot_delay` and `fakehttp.main.boot_delay`.
- Produces: one-time marker `taoistfuchen.main.boot_delay_migrated_r3=1`.
- Consumes later: lifecycle helpers read the same `boot_delay` fields; no alternate option name is allowed.

- [ ] **Step 1: Run the untouched r2 baseline**

Run:

```bash
./tests/run.sh
git status --short
```

Expected: `all tests: ok`; only the already committed plan/spec are present, with a clean worktree before RED edits.

- [ ] **Step 2: Write failing LuCI/default/release tests**

Create `tests/test_luci_boot_delay.js` so it reads both real view files, extracts the existing `validInteger()` function, evaluates it, and asserts:

```javascript
const accepted = [ '0', '1', '40', '60', '600' ];
const rejected = [ '', '-1', '-0', '+1', '00', '01', '1.0', '600.0', ' 1', '1 ', '601', 'abc' ];
```

The same test must assert that the source block between `'enabled'` and the interface option contains:

```javascript
form.Value, 'boot_delay'
validInteger(value, 0, 600)
o.rmempty = false
```

and that the two defaults are exactly `'40'` and `'60'`. Add this command to `tests/run.sh`:

```sh
node "$ROOT/tests/test_luci_boot_delay.js"
```

Add to `tests/test_release.py`:

```python
assert "PKG_RELEASE:=3" in makefile
assert "option boot_delay '60'" in fakehttp_cfg
assert "option boot_delay '40'" in fakesip_cfg
assert "uci -q delete fakehttp.main.boot_delay" not in defaults
assert "uci -q delete fakesip.main.boot_delay" not in defaults
assert "migrate_r3_boot_delays" in defaults
assert "taoistfuchen.main.boot_delay_migrated_r3" in defaults
assert "boot_delay_migrated_r3" not in text(PKG / "root/etc/config/taoistfuchen")
```

- [ ] **Step 3: Write failing migration tests for option B**

Extend `tests/test_migration.sh` to extract the production helper using:

```sh
eval "$(sed -n '/^migrate_r3_boot_delays()/,/^}/p' "$DEFAULTS")"
```

Use the existing UCI stub pattern to verify:

```text
marker absent, old 17/599  -> 40/60/marker 1
marker 1, user 7/8        -> preserve 7/8, no writes
marker 0 or invalid       -> 40/60/marker 1
commit fakesip failure    -> non-zero, marker absent
commit fakehttp failure   -> non-zero, marker absent
```

- [ ] **Step 4: Verify the RED failures are caused by missing behavior**

Run:

```bash
node tests/test_luci_boot_delay.js
sh tests/test_migration.sh
python3 tests/test_release.py
```

Expected: failures name missing `boot_delay`, missing `migrate_r3_boot_delays`, old `PKG_RELEASE:=2`, or the two active `uci delete` lines. Syntax/fixture errors are not acceptable RED evidence.

- [ ] **Step 5: Add UCI defaults and LuCI fields**

Immediately after `option enabled` add:

```uci
# /etc/config/fakesip
option boot_delay '40'
```

```uci
# /etc/config/fakehttp
option boot_delay '60'
```

Immediately after each Enable option add this LuCI shape, using `40` for FakeSIP and `60` for FakeHTTP:

```javascript
o = s.taboption('basic', form.Value, 'boot_delay',
	_('Boot auto-start delay (seconds)'),
	_('Only delays automatic service startup during router boot. Enabling, disabling, or applying settings from this page takes effect immediately.'));
o.default = '40';
o.rmempty = false;
o.validate = function(sectionId, value) {
	return validInteger(value, 0, 600) ||
		_('Enter an integer from 0 to 600 without leading zeros. Use 0 for no delay.');
};
```

The validator must not depend on the service-enabled flag.

- [ ] **Step 6: Implement the one-time r3 migration**

Delete both `uci -q delete ...boot_delay` lines. Add this helper and call it after both service main sections exist:

```sh
migrate_r3_boot_delays() {
	local marker

	marker="$(uci -q get taoistfuchen.main.boot_delay_migrated_r3 2>/dev/null || true)"
	[ "$marker" = '1' ] && return 0

	uci -q set fakesip.main.boot_delay=40 || return 1
	uci -q set fakehttp.main.boot_delay=60 || return 1
	uci -q commit fakesip || return 1
	uci -q commit fakehttp || return 1
	uci -q set taoistfuchen.main.boot_delay_migrated_r3=1 || return 1
	uci -q commit taoistfuchen
}
```

Call it with failure propagation so the uci-defaults file is not deleted after a partial migration:

```sh
migrate_r3_boot_delays || {
	logger -t taoistfuchen "unable to complete the r3 boot-delay migration" 2>/dev/null || true
	exit 1
}
```

Set `PKG_RELEASE:=3` without changing `PKG_VERSION:=2.1.0`.

- [ ] **Step 7: Verify GREEN and commit**

Run:

```bash
node tests/test_luci_boot_delay.js
sh tests/test_migration.sh
python3 tests/test_release.py
node --check luci-app-taoistfuchen/htdocs/luci-static/resources/view/taoistfuchen/fakesip.js
node --check luci-app-taoistfuchen/htdocs/luci-static/resources/view/taoistfuchen/fakehttp.js
sh -n luci-app-taoistfuchen/root/etc/uci-defaults/99_taoistfuchen
git diff --check
```

Expected: all targeted tests exit 0.

Commit:

```bash
git add tests/test_luci_boot_delay.js tests/run.sh tests/test_release.py \
  tests/test_migration.sh luci-app-taoistfuchen/Makefile \
  luci-app-taoistfuchen/root/etc/config/fakesip \
  luci-app-taoistfuchen/root/etc/config/fakehttp \
  luci-app-taoistfuchen/root/etc/uci-defaults/99_taoistfuchen \
  luci-app-taoistfuchen/htdocs/luci-static/resources/view/taoistfuchen/fakesip.js \
  luci-app-taoistfuchen/htdocs/luci-static/resources/view/taoistfuchen/fakehttp.js
git commit -m "feat: configure r3 boot delays"
```

---

### Task 2: Root-only delay state, one-shot runner, and internal procd scheduler

**Files:**
- Create: `tests/test_boot_delay.sh`
- Modify: `tests/run.sh`
- Modify: `tests/test_service_common.sh`
- Modify: `tests/test_release.py`
- Modify: `luci-app-taoistfuchen/root/usr/share/taoistfuchen/service-common.sh`
- Create: `luci-app-taoistfuchen/root/usr/share/taoistfuchen/boot-delay-runner.sh`
- Create: `luci-app-taoistfuchen/root/etc/init.d/taoistfuchen-boot-delay`

**Interfaces:**
- State directory: `${TF_BOOT_STATE_DIR:-/var/run/taoistfuchen-boot-delay}`, mode 0700.
- Uptime source: `${TF_UPTIME_FILE:-/proc/uptime}`.
- Boot state line: `<phase> <token> <deadline>`, with phase `wait|manual|done|cancel`.
- Link state line: `<phase> <generation>`, with phase `unknown|up|down` and a monotonically increasing generation.
- Per-service lifecycle lock: `${TF_BOOT_STATE_DIR}/<service>.lock`, acquired with `flock` before every boot/link state transition.
- Shared functions: `tf_boot_delay_value`, `tf_boot_uptime`, `tf_boot_state_set`, `tf_boot_state_get`, `tf_boot_state_is`, `tf_boot_state_clear`, `tf_boot_remaining`, `tf_boot_should_defer`, `tf_lifecycle_lock_acquire`, `tf_lifecycle_lock_release`, `tf_link_state_set`, `tf_link_state_get`, `tf_link_state_is_down`.
- Scheduler context passed to target init: internal command `boot_expired <token> <deadline>`; the runner never changes `wait` to `done` itself.

- [ ] **Step 1: Write the failing shared-state and scheduler tests**

Create `tests/test_boot_delay.sh` using a temporary `TF_BOOT_STATE_DIR` and a fake uptime file. Assert:

```text
tf_boot_delay_value 0 40   -> 0
tf_boot_delay_value 600 40 -> 600
tf_boot_delay_value 601 40 -> 40
tf_boot_delay_value 00 40  -> 40
uptime 11, delay 40        -> remaining 29
uptime 40, delay 40        -> remaining 0
wait token mismatch        -> runner never calls target init
manual/cancel state        -> runner never calls target init
matching wait at deadline  -> exactly one boot_expired command; target init owns the atomic wait-to-done transition
stop wins before claim     -> runner cannot produce a late start
```

Stub all procd functions and source a rewritten scheduler copy, then assert that enabled FakeSIP/FakeHTTP create two distinct instances with deadlines 40 and 60 and no `respawn` parameter. Add the new test to `tests/run.sh`.

Add release assertions that both new files exist, are executable, scheduler `START=98`, and neither init/hotplug contains a detached `sleep ... &` pattern.

- [ ] **Step 2: Run RED**

Run:

```bash
sh tests/test_boot_delay.sh
sh tests/test_service_common.sh
python3 tests/test_release.py
```

Expected: missing state functions/files/scheduler assertions fail.

- [ ] **Step 3: Implement the shared state contract**

Append BusyBox-ash-compatible helpers to `service-common.sh`. The implementation must use the following validation and atomic-write shape:

```sh
TF_BOOT_STATE_DIR="${TF_BOOT_STATE_DIR:-/var/run/taoistfuchen-boot-delay}"
TF_UPTIME_FILE="${TF_UPTIME_FILE:-/proc/uptime}"

tf_boot_delay_value() {
	local value="$1" fallback="$2"
	tf_valid_uint_range "$value" 0 600 || value="$fallback"
	printf '%s\n' "$value"
}

tf_boot_uptime() {
	local value rest
	IFS=' ' read -r value rest < "$TF_UPTIME_FILE" || return 1
	value="${value%%.*}"
	tf_valid_uint_range "$value" 0 4294967295 || return 1
	printf '%s\n' "$value"
}

tf_boot_state_path() {
	case "$1" in fakehttp|fakesip) ;; *) return 1 ;; esac
	printf '%s/%s.state\n' "$TF_BOOT_STATE_DIR" "$1"
}

tf_boot_state_set() {
	local service="$1" phase="$2" token="$3" deadline="$4" path tmp
	case "$phase" in wait|manual|done|cancel) ;; *) return 1 ;; esac
	case "$token" in ''|*[!A-Za-z0-9_.-]*) return 1 ;; esac
	tf_valid_uint_range "$deadline" 0 600 || return 1
	path="$(tf_boot_state_path "$service")" || return 1
	[ ! -L "$TF_BOOT_STATE_DIR" ] || return 1
	mkdir -p "$TF_BOOT_STATE_DIR" || return 1
	chmod 0700 "$TF_BOOT_STATE_DIR" || return 1
	tmp="$TF_BOOT_STATE_DIR/.${service}.$$"
	umask 077
	printf '%s %s %s\n' "$phase" "$token" "$deadline" > "$tmp" || return 1
	chmod 0600 "$tmp" || { rm -f "$tmp"; return 1; }
	mv -f "$tmp" "$path"
}
```

Implement the remaining named interfaces by reading only one validated line, rejecting symlinks/non-regular files, and computing `max(delay - uptime, 0)`. `tf_boot_should_defer` must return true for a matching `wait` state, for `cancel`, or when no `manual/done` state exists and uptime is below the delay. Lifecycle lock acquisition must use a root-only regular lock file and a dedicated fd distinct from procd's fd 1000. Link-state writes use the same atomic temp-file pattern and may occur only while that lifecycle lock is held.

- [ ] **Step 4: Implement the one-shot runner**

Create executable `boot-delay-runner.sh` with strict service/token/deadline validation. Its core loop must be condition-based and cancelable:

```sh
while tf_boot_state_is "$service" wait "$token" "$deadline"; do
	now="$(tf_boot_uptime)" || exit 1
	[ "$now" -lt "$deadline" ] || break
	sleep 1
done

tf_boot_state_is "$service" wait "$token" "$deadline" || exit 0
"${TF_INIT_DIR:-/etc/init.d}/$service" boot_expired "$token" "$deadline"
```

The script must not daemonize, must not respawn itself, and must never write a
`done` state. This prevents it from overwriting an explicit stop that wins the
target service's lifecycle lock immediately before expiry.

- [ ] **Step 5: Implement the internal scheduler**

Create executable `root/etc/init.d/taoistfuchen-boot-delay` with:

```sh
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=98
STOP=09
```

For each service/default pair (`fakesip 40`, `fakehttp 60`):

1. acquire that target service's lifecycle lock, load UCI, and for a disabled
   service replace any pending `wait` state with `cancel disabled 0`;
2. normalize delay;
3. skip `manual`, `done`, or `cancel` states before changing anything;
4. create/reuse a validated `wait` token and target deadline, then release the
   lifecycle lock;
5. if the normalized delay is `0`, invoke `boot_expired` immediately without
   creating a runner instance;
6. use the delay value itself as target uptime;
7. if already expired, invoke the target's `boot_expired` command;
8. otherwise register one procd runner instance;
9. omit `respawn`, set stdout/stderr and `term_timeout 2`.

The scheduler `service_stopped()` may invalidate only `wait` states; it must not erase `manual` or `done` states while the same boot is active.

Every `boot_expired` invocation must pass the exact token and deadline as
positional arguments, including the already-expired branch. `service_stopped()`
must acquire each target lifecycle lock before invalidating only `wait` states.

- [ ] **Step 6: Verify GREEN and commit**

Before verification, set source modes explicitly so the package remains valid
when committed or uploaded through GitHub:

```bash
chmod 0755 \
  luci-app-taoistfuchen/root/usr/share/taoistfuchen/boot-delay-runner.sh \
  luci-app-taoistfuchen/root/etc/init.d/taoistfuchen-boot-delay \
  tests/test_boot_delay.sh
```

Run:

```bash
sh tests/test_boot_delay.sh
sh tests/test_service_common.sh
python3 tests/test_release.py
sh -n luci-app-taoistfuchen/root/usr/share/taoistfuchen/service-common.sh
sh -n luci-app-taoistfuchen/root/usr/share/taoistfuchen/boot-delay-runner.sh
sh -n luci-app-taoistfuchen/root/etc/init.d/taoistfuchen-boot-delay
git diff --check
```

Expected: all targeted tests pass; no real 40/60-second wait occurs in tests.

Commit:

```bash
git add tests/test_boot_delay.sh tests/run.sh tests/test_service_common.sh \
  tests/test_release.py \
  luci-app-taoistfuchen/root/usr/share/taoistfuchen/service-common.sh \
  luci-app-taoistfuchen/root/usr/share/taoistfuchen/boot-delay-runner.sh \
  luci-app-taoistfuchen/root/etc/init.d/taoistfuchen-boot-delay
git commit -m "feat: supervise boot delay scheduling"
```

---

### Task 3: Integrate manual/boot/ifdown/ifup contexts into the real services

**Files:**
- Create: `tests/test_hotplug.sh`
- Modify: `tests/run.sh`
- Modify: `tests/test_service_commands.sh`
- Modify: `tests/test_release.py`
- Modify: `luci-app-taoistfuchen/root/etc/init.d/fakesip`
- Modify: `luci-app-taoistfuchen/root/etc/init.d/fakehttp`
- Modify: `luci-app-taoistfuchen/root/etc/hotplug.d/iface/99-taoistfuchen`
- Modify: `luci-app-taoistfuchen/root/etc/uci-defaults/99_taoistfuchen`
- Modify: `luci-app-taoistfuchen/Makefile`

**Interfaces:**
- Context variable: `TAOISTFUCHEN_SERVICE_CONTEXT=auto|ifup|boot-expired|ifdown-definition`.
- Internal rc.common commands: `link_down <device>`, `link_up <device>`, and `boot_expired <token> <deadline>`.
- Unset context plus rc.common `action=boot` means boot; unset context plus start/reload/restart means manual.
- `link_down` holds the target procd lock, records link `down` before any kill, calls `procd_kill`, cleans nft only after the kill, then submits an empty definition so reload triggers remain registered. It does not cancel a boot wait.
- `link_up` holds the same lock, records link `up`, and starts only when the boot gate permits it.
- `stop_service()` invalidates a wait before rc.common performs `procd_kill`; `service_stopped()` performs nft cleanup after that kill.

- [ ] **Step 1: Write failing service-context tests**

Extend the existing init harness to stub the Task 2 state helpers and assert for both services:

```text
action=boot, delay 40/60, uptime 11 -> no binary command, no interface validation failure
context=auto inside window          -> no binary command
command=boot_expired, matching wait -> atomically done + normal binary command
plain action=start/reload, delay600 -> immediate normal binary command and manual state
command=link_down                   -> state down, kill, cleanup, empty definition; no validation
command=link_up inside wait         -> state up, no binary command
command=link_up after deadline      -> state up, normal binary command
enabled=0 during pending wait       -> cancel state, no command
explicit stop vs runner             -> whichever gets the target lock first determines the final state, with no late resurrection
```

Keep all existing FakeHTTP/FakeSIP command-vector assertions unchanged.

- [ ] **Step 2: Write failing hotplug tests**

Create `tests/test_hotplug.sh`. Rewrite hard-coded init paths into a temporary directory, provide fake init scripts that log context/action, and stub UCI. Cover:

```text
matching DEVICE + ifdown -> link_down DEVICE
matching existing DEVICE + ifup -> link_up DEVICE
nonmatching DEVICE       -> no command
missing DEVICE + resolvable INTERFACE -> resolve the unique L3 device and handle it
ifup DEVICE then ifdown without DEVICE -> use the root-only INTERFACE/L3 cache
missing/unresolvable device -> no command and diagnostic logger call
disabled service         -> no command
FakeHTTP mode all        -> matches explicit existing DEVICE
```

Add it to `tests/run.sh`.

- [ ] **Step 3: Verify RED**

Run:

```bash
sh tests/test_service_commands.sh
sh tests/test_hotplug.sh
python3 tests/test_release.py
```

Expected: current scripts still validate PPPoE during boot, hotplug still logs `reload` for both actions, the link commands do not exist, and the new ordering/race assertions fail.

- [ ] **Step 4: Implement the init context gate before interface validation**

In each service define:

```sh
SERVICE_NAME=fakesip       # fakehttp in the sibling script
DEFAULT_BOOT_DELAY=40      # 60 for fakehttp
```

After `config_load` and `enabled` lookup, derive context in this order:

```sh
context="${TAOISTFUCHEN_SERVICE_CONTEXT:-}"
if [ -z "$context" ]; then
	case "${action:-start}" in
		boot) context=boot ;;
		*) context=manual ;;
	esac
fi
```

Put the existing command construction in `start_service_locked()` and wrap it
with lifecycle-lock acquire/release. Apply this state machine before
binary/interface validation:

```sh
case "$context" in
	ifdown-definition)
		return 0
		;;
	manual)
		if [ "$enabled" = 1 ]; then
			tf_boot_state_set "$SERVICE_NAME" manual manual 0 || return 1
		else
			tf_boot_state_set "$SERVICE_NAME" cancel manual 0 || return 1
			return 0
		fi
		;;
	boot-expired)
		token="${TAOISTFUCHEN_BOOT_TOKEN:-}"
		deadline="${TAOISTFUCHEN_BOOT_DEADLINE:-}"
		tf_boot_state_is "$SERVICE_NAME" wait "$token" "$deadline" || return 0
		if [ "$enabled" != 1 ]; then
			tf_boot_state_set "$SERVICE_NAME" cancel disabled 0 || return 1
			return 0
		fi
		tf_boot_state_set "$SERVICE_NAME" done "$token" "$deadline" || return 1
		tf_link_state_is_down "$SERVICE_NAME" && return 0
		;;
	boot|auto|ifup)
		config_get boot_delay main boot_delay "$DEFAULT_BOOT_DELAY"
		boot_delay="$(tf_boot_delay_value "$boot_delay" "$DEFAULT_BOOT_DELAY")"
		if [ "$enabled" != 1 ]; then
			tf_boot_state_set "$SERVICE_NAME" cancel disabled 0 || return 1
			return 0
		fi
		tf_boot_should_defer "$SERVICE_NAME" "$boot_delay" && return 0
		tf_boot_state_set "$SERVICE_NAME" done automatic "$boot_delay" || return 1
		;;
	*)
		return 1
		;;
esac
```

Then run the existing executable check, full validation and unchanged command assembly. Keep service reload triggers even when no instance is created. State cancellation belongs in `stop_service()` before the kill; `service_stopped()` only retains the existing post-kill nft cleanup.

Immediately before any path that will validate/start a main instance, call
`( procd_kill "$SERVICE_NAME" )` in a child shell and then clean that service's
nft table. The child is required because OpenWrt 25.12.5 `_procd_kill()` calls
`json_init/json_cleanup`; a direct call would destroy the parent shell's
in-progress rc_procd JSON. The isolated kill guarantees old-process termination
precedes cleanup without corrupting the new definition.

Add `context`, `boot_delay`, `token`, and `deadline` to each `start_service()`
local declaration. The `boot-expired` branch must re-check `enabled` after
validating the scheduler token so a direct UCI disable cannot produce a late
start even when no LuCI reload was issued.

Implement `stop_service()` so `stop|shutdown|restart` changes a pending boot
state to `cancel explicit-stop 0` while holding the lifecycle lock, before
rc.common's subsequent `procd_kill`. `restart` then enters the normal manual
start branch and becomes immediate. `service_stopped()` only performs post-kill
nft cleanup.

Implement the three internal commands with `EXTRA_COMMANDS`:

```sh
link_down() {
	# procd lock + lifecycle lock are held across all operations
	tf_link_state_set "$SERVICE_NAME" down || return 1
	procd_kill "$SERVICE_NAME"
	tf_cleanup_nft_table "$SERVICE_NAME"
	TAOISTFUCHEN_SERVICE_CONTEXT=ifdown-definition start
}

link_up() {
	tf_link_state_set "$SERVICE_NAME" up || return 1
	TAOISTFUCHEN_SERVICE_CONTEXT=ifup start
}

boot_expired() {
	TAOISTFUCHEN_SERVICE_CONTEXT=boot-expired \
		TAOISTFUCHEN_BOOT_TOKEN="$1" \
		TAOISTFUCHEN_BOOT_DEADLINE="$2" start
}
```

The real implementation must explicitly call `procd_lock` and hold the same
lifecycle lock across each nested `start`; the shared lock's counted
same-service reentry keeps the outer lock held until the extra command exits.
`boot_expired` must pre-check the exact wait token
before invoking nested `start`, otherwise a stale timer would submit an empty
definition. `link_down/link_up` must reload enabled/interface settings after
acquiring the lock and no-op if the event device no longer matches.

- [ ] **Step 5: Replace hotplug reload with explicit transitions**

Source the shared helper and `/lib/functions/network.sh`. Prefer a non-empty,
syntactically valid `DEVICE`. If it is absent, resolve `INTERFACE` with
`network_get_device`; accept only one validated L3 device. Every successful
ifup atomically caches `INTERFACE -> L3 DEVICE` in the root-only runtime state;
ifdown may use that exact cache only after live L3 resolution fails. Never use
the physical `.device` fallback for PPPoE. For `ifup`, require the resolved
device exists. Preserve current device matching and use:

```sh
case "$ACTION" in
	ifdown) command=link_down ;;
	ifup)   command=link_up ;;
	*)      return 0 ;;
esac

"/etc/init.d/$tf_service" "$command" "$tf_device" >/dev/null 2>&1 || true
```

If `DEVICE` is missing/unresolvable or resolves ambiguously, log and skip; never
guess and never invoke an unrelated service. Do not call `reload` from hotplug.

- [ ] **Step 6: Mark uci-defaults starts as automatic and manage scheduler lifecycle**

In `99_taoistfuchen`, enable/start `taoistfuchen-boot-delay`. Start FakeHTTP/FakeSIP with:

```sh
TAOISTFUCHEN_SERVICE_CONTEXT=auto "/etc/init.d/$svc" start
```

This makes an online install with uptime above the deadline immediate, while first boot respects the remaining window.

In `Package/luci-app-taoistfuchen/prerm`, stop/disable the internal scheduler as well as the three existing services and remove `/var/run/taoistfuchen-boot-delay`.

- [ ] **Step 7: Verify GREEN and commit**

Run:

```bash
sh tests/test_service_commands.sh
sh tests/test_hotplug.sh
sh tests/test_boot_delay.sh
python3 tests/test_release.py
sh -n luci-app-taoistfuchen/root/etc/init.d/fakesip
sh -n luci-app-taoistfuchen/root/etc/init.d/fakehttp
sh -n luci-app-taoistfuchen/root/etc/hotplug.d/iface/99-taoistfuchen
sh -n luci-app-taoistfuchen/root/etc/uci-defaults/99_taoistfuchen
git diff --check
```

Expected: all context/hotplug tests pass and old command vectors remain identical.

Commit:

```bash
git add tests/test_service_commands.sh tests/test_hotplug.sh tests/test_boot_delay.sh \
  tests/run.sh tests/test_release.py luci-app-taoistfuchen/Makefile \
  luci-app-taoistfuchen/root/etc/init.d/fakesip \
  luci-app-taoistfuchen/root/etc/init.d/fakehttp \
  luci-app-taoistfuchen/root/etc/hotplug.d/iface/99-taoistfuchen \
  luci-app-taoistfuchen/root/etc/uci-defaults/99_taoistfuchen
git commit -m "fix: separate WAN down and up lifecycle"
```

---

### Task 4: Correct FakeSIP reporting and release maintained version 0.9.5

**Files:**
- Modify: `tests/test_fakesip_source.py`
- Modify: `luci-app-taoistfuchen/src/fakesip/src/mainfun.c`
- Modify: `luci-app-taoistfuchen/src/fakesip/include/globvar.h`
- Modify: `luci-app-taoistfuchen/src/fakesip/src/globvar.c`
- Modify: `luci-app-taoistfuchen/src/fakesip/README.md`
- Modify: `luci-app-taoistfuchen/src/fakesip/README.TaoistFuchen.md`
- Modify: `luci-app-taoistfuchen/src/fakesip/Makefile`
- Modify: `luci-app-taoistfuchen/src/Makefile`
- Modify: `luci-app-taoistfuchen/root/etc/init.d/fakesip`
- Modify: `THIRD_PARTY_SOURCES.md`
- Delete: `third_party/sources/FakeSIP-TaoistFuchen-0.9.4.tar.gz`
- Create: `third_party/sources/FakeSIP-TaoistFuchen-0.9.5.tar.gz`
- Modify: `third_party/SHA256SUMS`

**Interfaces:**
- Produces binary marker `FakeSIP version 0.9.5`.
- Preserves direction mapping and packet-core source.
- Produces corresponding source archive root `FakeSIP-TaoistFuchen-0.9.5/`.

- [ ] **Step 1: Write failing source/reporting tests**

Add exact assertions to `tests/test_fakesip_source.py` for:

```python
assert '"  -0                 process outbound packets\\n"' in mainfun
assert '"  -1                 process inbound packets\\n"' in mainfun
assert 'ipproto_info = " (IPv4 and IPv6)";' in mainfun
assert 'direction_info = " (outbound only)";' in mainfun
assert 'direction_info = " (inbound only)";' in mainfun
assert 'direction_info = " (inbound and outbound)";' in mainfun
```

Also lock the unchanged data path:

```python
assert "g_ctx.inbound = 1;" in mainfun[mainfun.index("case '0':"):mainfun.index("case '1':")]
assert "g_ctx.outbound = 1;" in mainfun[mainfun.index("case '1':"):mainfun.index("case '4':")]
assert "if (!g_ctx.outbound)" in packet_host_branch
assert "if (!g_ctx.inbound)" in packet_outgoing_branch
```

Change archive/version expectations to `0.9.5` before implementation.

- [ ] **Step 2: Run RED**

Run:

```bash
python3 tests/test_fakesip_source.py
```

Expected: old `inbound`/`outbound` strings, blank dual/both strings, 0.9.4 Makefiles and missing 0.9.5 archive fail.

- [ ] **Step 3: Make the minimal expression-layer change**

In `mainfun.c` use:

```c
"  -0                 process outbound packets\n"
"  -1                 process inbound packets\n"
```

and:

```c
if (g_ctx.use_ipv4 && !g_ctx.use_ipv6) {
    ipproto_info = " (IPv4 only)";
} else if (!g_ctx.use_ipv4 && g_ctx.use_ipv6) {
    ipproto_info = " (IPv6 only)";
} else {
    ipproto_info = " (IPv4 and IPv6)";
}

if (g_ctx.inbound && !g_ctx.outbound) {
    direction_info = " (outbound only)";
} else if (!g_ctx.inbound && g_ctx.outbound) {
    direction_info = " (inbound only)";
} else {
    direction_info = " (inbound and outbound)";
}
```

Change both Makefiles to 0.9.5. Update FakeSIP README usage and add legacy-name comments to `globvar.h/.c`; do not rename fields or edit `nfqueue.c`/`rawsend.c`. Update the init comment without changing its three direction branches.

Update the current maintained-source heading, archive filename, maintenance
delta and real archive digest in `THIRD_PARTY_SOURCES.md` in this same task so
`tests/test_fakesip_source.py` can pass without temporarily lying about
provenance.

- [ ] **Step 4: Format and generate the deterministic corresponding source**

Run clang-format 18 on only changed C/H files, then verify the full tree:

```bash
clang-format-18 -i \
  luci-app-taoistfuchen/src/fakesip/src/mainfun.c \
  luci-app-taoistfuchen/src/fakesip/src/globvar.c \
  luci-app-taoistfuchen/src/fakesip/include/globvar.h
clang-format-18 --dry-run --Werror \
  luci-app-taoistfuchen/src/fakesip/src/*.c \
  luci-app-taoistfuchen/src/fakesip/include/*.h
```

Create the archive:

```bash
set -eu
archive_root='FakeSIP-TaoistFuchen-0.9.5'
source_dir='luci-app-taoistfuchen/src/fakesip'
archive='third_party/sources/FakeSIP-TaoistFuchen-0.9.5.tar.gz'
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT INT TERM
mkdir -p "$temporary/$archive_root"
rsync -a --exclude='build/' "$source_dir/" "$temporary/$archive_root/"
tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
  --mode='u+rwX,go+rX,go-w' --format=gnu -C "$temporary" \
  -cf - "$archive_root" | gzip -n > "$archive"
rm -f third_party/sources/FakeSIP-TaoistFuchen-0.9.4.tar.gz
sha256sum "$archive"
```

Use the real digest to update `third_party/SHA256SUMS`.

- [ ] **Step 5: Verify GREEN and commit the inseparable source unit**

Run:

```bash
python3 tests/test_fakesip_source.py
sh tests/test_service_commands.sh
sha256sum -c third_party/SHA256SUMS
clang-format-18 --dry-run --Werror \
  luci-app-taoistfuchen/src/fakesip/src/*.c \
  luci-app-taoistfuchen/src/fakesip/include/*.h
git diff --check
```

Expected: source/archive equality passes and direction command tests still prove outbound `-0`, inbound `-1`.

Commit source, version, archive and checksum together:

```bash
git add luci-app-taoistfuchen/src/fakesip luci-app-taoistfuchen/src/Makefile \
  luci-app-taoistfuchen/root/etc/init.d/fakesip tests/test_fakesip_source.py \
  THIRD_PARTY_SOURCES.md third_party/SHA256SUMS third_party/sources
git commit -m "fix: release FakeSIP 0.9.5 reporting"
```

---

### Task 5: Release metadata, documentation, artifact gates, and full regression

**Files:**
- Modify: `README.md`
- Modify: `THIRD_PARTY_SOURCES.md`
- Modify: `GITHUB_WEB_UPLOAD.md`
- Modify: `luci-app-taoistfuchen/Makefile`
- Modify: `luci-app-taoistfuchen/htdocs/luci-static/resources/view/taoistfuchen/fakesip.js`
- Modify: `scripts/prepare-artifact.sh`
- Modify: `scripts/verify-built-apk.py`
- Modify: `scripts/normalize-source-permissions.sh`
- Modify: `tests/test_release.py`
- Modify: `tests/test_build_pipeline.sh`

**Interfaces:**
- APK metadata `2.1.0-r3`.
- Artifact includes only main APK plus licenses and FakeHTTP/FakeSIP corresponding sources.
- APK verifier requires 0.9.5, correct direction usage, explicit direction modes, and explicit dual-stack string.

- [ ] **Step 1: Write failing release/artifact assertions**

Change build fixtures and tests to require:

```text
luci-app-taoistfuchen-2.1.0-r3.apk
version: 2.1.0-r3
FakeSIP version 0.9.5
FakeSIP-TaoistFuchen-0.9.5.tar.gz
```

Add APK marker requirements:

```python
b"process outbound packets",
b"process inbound packets",
b"IPv4 and IPv6",
b"outbound only",
b"inbound only",
b"inbound and outbound",
```

Create a stale-reporting ELF fixture with correct architecture/version/IPv6 marker but missing these strings and assert the collector rejects it.

Release tests must require README statements for 40/60, `0–600`, manual immediacy, parallel timers, `ifdown` stop-only, and waiting-window `ifup` suppression.

- [ ] **Step 2: Run RED**

Run:

```bash
sh tests/test_build_pipeline.sh
python3 tests/test_release.py
```

Expected: verifier/collector/docs still contain 0.9.4/r2 or do not reject stale reporting.

- [ ] **Step 3: Update current product references and lifecycle documentation**

Update only current release references:

```make
PKG_VERSION:=2.1.0
PKG_RELEASE:=3
```

Set package/LuCI descriptions to FakeSIP 0.9.5. Update README with the exact lifecycle matrix from the design, including scheme B's one-time reset. Update `THIRD_PARTY_SOURCES.md` to 0.9.5 and its real archive digest. Update the GitHub upload example to r3. Do not rewrite historical plan/spec version numbers.

- [ ] **Step 4: Update artifact and executable-permission paths**

`prepare-artifact.sh` must copy 0.9.5 and reject absence. `verify-built-apk.py` must expect r3 and all marker strings. `normalize-source-permissions.sh` and uci-defaults chmod lists must include:

```text
/etc/init.d/taoistfuchen-boot-delay
/usr/share/taoistfuchen/boot-delay-runner.sh
```

The package prerm must stop/disable the scheduler and remove its state directory.

- [ ] **Step 5: Verify GREEN, run the full suite, and commit**

Run:

```bash
sh scripts/normalize-source-permissions.sh
./tests/run.sh
sha256sum -c third_party/SHA256SUMS
git diff --check
```

Expected: every test prints its `ok` marker and the suite ends `all tests: ok`.

Commit:

```bash
git add README.md THIRD_PARTY_SOURCES.md GITHUB_WEB_UPLOAD.md \
  luci-app-taoistfuchen/Makefile \
  luci-app-taoistfuchen/htdocs/luci-static/resources/view/taoistfuchen/fakesip.js \
  luci-app-taoistfuchen/root/etc/uci-defaults/99_taoistfuchen \
  scripts/prepare-artifact.sh scripts/verify-built-apk.py \
  scripts/normalize-source-permissions.sh tests/test_release.py \
  tests/test_build_pipeline.sh
git commit -m "chore: release TaoistFuchen 2.1.0-r3"
```

---

### Task 6: Official SDK build, APK inspection, source ZIP, and deliverables

**Files:**
- Generate outside Git: `luci-app-taoistfuchen-2.1.0-r3.apk`
- Generate outside Git: `OpenWrt-TaoistFuchen-v2.1.0-r3-source.zip`
- Generate outside Git: `luci-app-taoistfuchen-2.1.0-r3-Actions-artifact.zip`
- Generate outside Git: `FakeSIP-TaoistFuchen-0.9.5.tar.gz`
- Generate outside Git: `SHA256SUMS`

**Interfaces:**
- Uses the exact SDK filename/SHA-256 pinned in `.github/workflows/build.yml`.
- Produces one installable AArch64 APK and no bundled dependency APKs.

- [ ] **Step 1: Run fresh completion gates**

Run:

```bash
./tests/run.sh
sha256sum -c third_party/SHA256SUMS
clang-format-18 --dry-run --Werror \
  luci-app-taoistfuchen/src/fakesip/src/*.c \
  luci-app-taoistfuchen/src/fakesip/include/*.h
git diff --check
git status --short
```

Expected: all commands exit 0 and the tracked worktree is clean.

- [ ] **Step 2: Build with the pinned OpenWrt 25.12.5 SDK**

Use the SDK named in `.github/workflows/build.yml`:

```bash
SDK_FILE='openwrt-sdk-25.12.5-mediatek-mt7622_gcc-14.3.0_musl.Linux-x86_64.tar.zst'
SDK_SHA256='0bd25a391256dbe9ad1f9c6f313364b1f9eddcc0e280c829d644034981ad8306'
BASE_URL='https://downloads.openwrt.org/releases/25.12.5/targets/mediatek/mt7622'

if [ ! -d openwrt-sdk ]; then
  wget -q "$BASE_URL/sha256sums" -O /tmp/openwrt-25.12.5-mt7622-sha256sums
  test "$(awk -v f="$SDK_FILE" '$2 == f || $2 == "*" f { print $1; exit }' \
    /tmp/openwrt-25.12.5-mt7622-sha256sums)" = "$SDK_SHA256"
  wget -q "$BASE_URL/$SDK_FILE" -O "/tmp/$SDK_FILE"
  printf '%s  %s\n' "$SDK_SHA256" "/tmp/$SDK_FILE" | sha256sum -c -
  SDK_DIR="$(tar -tf "/tmp/$SDK_FILE" | head -n 1 | cut -d/ -f1)"
  tar -xf "/tmp/$SDK_FILE"
  mv "$SDK_DIR" openwrt-sdk
fi

rm -rf openwrt-sdk/package/luci-app-taoistfuchen
cp -a luci-app-taoistfuchen openwrt-sdk/package/
sh scripts/configure-openwrt-sdk.sh openwrt-sdk
make -C openwrt-sdk package/luci-app-taoistfuchen/clean
make -C openwrt-sdk package/luci-app-taoistfuchen/compile -j1 V=s
```

Expected: exit 0 and exactly one `luci-app-taoistfuchen-2.1.0-r3.apk`.

- [ ] **Step 3: Verify APK metadata, ELF, strings, and dependencies**

Run:

```bash
APK="$(find openwrt-sdk/bin/packages/aarch64_cortex-a53 \
  -type f -name 'luci-app-taoistfuchen-2.1.0-r3.apk' -print -quit)"
test -n "$APK"
python3 scripts/verify-built-apk.py \
  openwrt-sdk/staging_dir/host/bin/apk "$APK"
```

Expand it and verify:

```bash
extract_dir="$(mktemp -d)"
openwrt-sdk/staging_dir/host/bin/apk --allow-untrusted extract --no-chown \
  --destination "$extract_dir" "$APK"
file "$extract_dir/usr/bin/fakesip"
test "$(stat -c '%a' "$extract_dir/usr/bin/fakesip")" = 755
strings "$extract_dir/usr/bin/fakesip" | rg -F \
  -e 'FakeSIP version 0.9.5' \
  -e 'process outbound packets' -e 'process inbound packets' \
  -e 'IPv4 and IPv6' -e 'outbound only' -e 'inbound only' \
  -e 'inbound and outbound'
readelf -d "$extract_dir/usr/bin/fakesip" | \
  rg 'libnetfilter_queue|libnfnetlink|libmnl'
```

Expected: 0755 AArch64 ELF, all markers present, dependency set unchanged.

- [ ] **Step 4: Prepare and validate the Actions-style artifact**

Run:

```bash
rm -rf output_pkg
sh scripts/prepare-artifact.sh openwrt-sdk output_pkg
test "$(find output_pkg -maxdepth 1 -type f -name '*.apk' | wc -l)" -eq 1
test -f output_pkg/FakeSIP-TaoistFuchen-0.9.5.tar.gz
test ! -e output_pkg/FakeSIP-TaoistFuchen-0.9.4.tar.gz
(cd output_pkg && sha256sum -c SHA256SUMS)
```

Expected: one main APK, licenses/source documents and both corresponding source archives; no dependency APKs.

- [ ] **Step 5: Generate source and delivery archives from the verified commit**

Run from a clean committed tree:

```bash
mkdir -p deliverables/v2.1.0-r3
git archive --format=zip \
  --prefix=OpenWrt-TaoistFuchen-v2.1.0-r3/ \
  -o deliverables/v2.1.0-r3/OpenWrt-TaoistFuchen-v2.1.0-r3-source.zip HEAD
cp "$APK" deliverables/v2.1.0-r3/
cp third_party/sources/FakeSIP-TaoistFuchen-0.9.5.tar.gz \
  deliverables/v2.1.0-r3/
(cd output_pkg && zip -X -r ../deliverables/v2.1.0-r3/luci-app-taoistfuchen-2.1.0-r3-Actions-artifact.zip .)
(cd deliverables/v2.1.0-r3 && sha256sum \
  OpenWrt-TaoistFuchen-v2.1.0-r3-source.zip \
  luci-app-taoistfuchen-2.1.0-r3.apk \
  luci-app-taoistfuchen-2.1.0-r3-Actions-artifact.zip \
  FakeSIP-TaoistFuchen-0.9.5.tar.gz > SHA256SUMS)
```

- [ ] **Step 6: Re-test the delivered source ZIP**

Run:

```bash
zip_test="$(mktemp -d)"
unzip -q deliverables/v2.1.0-r3/OpenWrt-TaoistFuchen-v2.1.0-r3-source.zip \
  -d "$zip_test"
cd "$zip_test/OpenWrt-TaoistFuchen-v2.1.0-r3"
./tests/run.sh
sha256sum -c third_party/SHA256SUMS
test -f luci-app-taoistfuchen/src/fakesip/.clang-format
```

Expected: the web-upload source ZIP independently passes all tests and includes hidden `.clang-format`.

- [ ] **Step 7: Final independent review and handoff**

Dispatch a reviewer with the design, base SHA, head SHA, test output, SDK build log and unpacked APK evidence. Fix every Critical/Important issue, rerun the affected RED/GREEN cycle and all completion gates, then report final commit and SHA-256 values. Do not commit SDK, APK, `output_pkg`, unpacked files, or delivery ZIPs into the repository.
