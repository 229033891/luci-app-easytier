# Web 控制台交互性能审查（OpenWrt / LuCI）

## Status

- Status: **Current**（P1/P2/P3 已修复，待真机复测）
- 最近审阅：2026-10-16（实施 P1–P3 修复：`/proc` 取代 `top`、curl 负缓存、CLI 缓存、日志增量；2026-10-15 首版逐行核实三个轮询页 + `act_status` / `act_conninfo` / `get_log` + init.d）
- 审查对象：`luci-app-easytier` 插件（LuCI Web 界面）
- 版本：`version.mk` → EasyTier **2.7.5**
- 代码位置：本仓 `luci-app-easytier/`
- **姊妹文档（ET Web 控制台 + 安卓 GUI）**：`D:\EasyTier\docs\current\console-and-client-interaction-performance.md` —— 本文 §5 的隧道争用结论在彼处有对称发现（两端轮询共用同一条隧道）

> 本文区分**已核实**（读代码）与**推断**。未在真实路由器上做 profiling。

---

## 1. 结论

**是，OpenWrt 侧代码确实会造成 Web 控制台卡顿，而且问题相当严重。**

三个页面各自有独立的后端重负载轮询，叠加起来在弱路由器上是**持续性的 CPU 与进程开销**：

| # | 页面 | 轮询间隔（修复后） | 每次后端开销 | 严重度 | 修复（2026-10-16） |
|---|------|----------|--------------|--------|------|
| **P1** | 状态页 | **3 s → 5 s** | `pgrep`×2 + ~~`top -b -n1`×2~~ + **`curl`(3s 超时)** + `io.popen`×5 | **极高** | 读 `/proc` 取代 `top`×2；curl **失败即负缓存**（TTL 30 min）；TUN 详情降频为每 2 次轮询（≈10 s） |
| **P2** | 连接信息页 | **5 s** | **11 个 `easytier-cli` 子进程**（无缓存） | **高** | 恢复 `/tmp/easytier-cli_*` 缓存（TTL 5 s，对齐 init.d 既有清理列表） |
| **P3** | 日志页 | **2 s → 5 s** | 全量读取日志文件（最大 **5 MB**）+ 全量 DOM 重建 | **极高** | `get_log` 增量返回（首屏 tail 128 KB + `offset` 续读，行对齐）；前端**追加**而非重建；轮转阈值 5120 KB → **1024 KB**；尺寸复用响应，省一次 `get_log_size` 请求 |

**并且与 RDP 卡顿存在直接因果链**（§5）：若 LuCI 是**通过 EasyTier 隧道**访问的，这些轮询流量本身就走这条隧道，与 RDP 抢带宽并触发发送队列丢包 —— 这正好解释了「打开 Web 控制台时 RDP 更卡」。

### 修复状态（2026-10-16）

P1/P2/P3 三条已按 §7 实施（建议 1–7；建议 8 未做）。代码改动：

- **后端** `luasrc/controller/easytier.lua`：新增 `read_ttl_cache` / `write_ttl_cache` / `read_proc_cpu` / `read_proc_rss_mb` / `read_log_incremental` 等 helper；
  - `act_status`：`top -b -n1`×2 → 读 `/proc/<pid>/stat`；`curl` 失败写负缓存（占位 `-` + 时间戳，TTL 30 min）；
  - `act_conninfo`：11 个 CLI 走 `/tmp/easytier-cli_*` 缓存（TTL 5 s，文件名与 init.d stop_service 清理列表一致）；
  - `get_log` / `get_wlog`：改为增量 JSON `{size, next_offset, reset, content}`，仅对增量做 ANSI 清理。
- **前端** `easytier_status.htm`：`XHR.poll(3→5)`、TUN 详情每 2 次轮询（≈10 s，速率换算 /3→/10）；`easytier_log.htm`：`setInterval(2→5)`、**追加**渲染、尺寸复用 `get_log` 响应的 `size`（省一次 `get_log_size`）。
- **init.d** `root/etc/init.d/easytier`：日志轮转阈值 5120 KB → **1024 KB**（core×2 + web）。

**行为变化（需真机确认）**：

1. 状态页 CPU 列改为**进程平均占用**（`(utime+stime)/uptime`），非瞬时值 —— 低负载长跑时数值偏小属预期。
2. 日志页首屏只取**最后 128 KB**；增量模式不回溯更早内容（清空重进即从头）。
3. 版本检测失败后 **30 分钟内不再重试**（负缓存），期间「新版本」提示可能滞后、显示为空。

---

## 2. P1 — 状态页：3 秒一次 `top` + 无负缓存的 `curl`

**前端**：`luasrc/view/easytier/easytier_status.htm:1077`

```js
XHR.poll(3, '<%=url("admin","vpn","easytier","api_status")%>', null, function(x, data) {
    updateStatus(data);
    updateTunInterface(data.crunning, data.no_tun, data.dev_name);  // ← 又发一个 XHR
    ...
});
```

**后端**：`luasrc/controller/easytier.lua:83-154` `act_status()`

每次调用依次执行：

| 操作 | 代码 | 说明 |
|------|------|------|
| `pgrep easytier-core` | `:88` | 进程扫描 |
| `pgrep easytier-web` | `:89` | 进程扫描 |
| **`top -b -n1 \| grep ... \| awk`** | `:99` | ⚠️ **最昂贵**：`top` 需遍历 `/proc` 并计算全部进程 CPU 并快照 |
| `cat /proc/<pid>/status \| grep VmRSS` | `:103` | 可接受 |
| **`top -b -n1` ×2**（web 进程） | `:107` | ⚠️ 再来一次 |
| `cat /proc/<pid>/status` | `:111` | 可接受 |
| **`curl` → api.github.com** | `:120` | ⚠️ 见下 |

### 2.1 `curl` 无负缓存 —— 自我 DoS

```lua
local cached_newtag = safe_read_file("/tmp/easytiernew.tag")
if cached_newtag and cached_newtag ~= "" then
    e.etnewtag = cached_newtag:gsub("[\r\n]+", "")
else
    e.etnewtag = safe_exec("curl -L -k -s --connect-timeout 3 ... https://api.github.com/...")
    if e.etnewtag ~= "" then          -- ← 只在成功时写缓存
        local f = io.open("/tmp/easytiernew.tag", "w")
        if f then f:write(e.etnewtag); f:close() end
    end
end
```

**失败路径不写缓存**。在访问不了 GitHub 的环境（OpenWrt 上非常常见：无 IPv6、DNS 受限、被墙）：

1. `curl` 每次耗满 **3 秒**超时 → 返回空
2. 空 → **不写缓存**
3. 3 秒后下一次轮询 → **再次发起 3 秒 `curl`**

轮询周期（3 s）**等于**超时（3 s），请求永不排空 → LuCI 后端被持续占满 → **页面卡死**。

> 正确做法：失败也要写负缓存（如 `"0"` + TTL），或把版本检查完全移出状态轮询。

### 2.2 二次 XHR 放大

`updateTunInterface()`（`easytier_status.htm:974-1074`）在**每个** 3 秒轮询回调里再发一个 XHR → `get_tun_info`（`:294-354`），后者又执行 `ip link` / `ifconfig` / `ip -4 addr`（可能 2 次）/ `ip -6 addr` / `cat` ×2。

⇒ 状态页实际是**每 3 秒两个 HTTP 请求 + 十余次进程派生**。

---

## 3. P2 — 连接信息页：5 秒 11 个 CLI 子进程

**前端**：`luasrc/view/easytier/easytier_cli.htm:1510`

```js
XHR.poll(5, '<%=url("admin","vpn","easytier","api_conninfo")%>', null, function(x, data) {
    if (!isRefreshing && data) { updateConnInfo(data); }
});
```

**后端**：`easytier.lua:629-694` `act_conninfo()` → `get_cli_output()`，**无任何缓存**，每次串行执行 **11 个** `easytier-cli` 子进程：

```
node, peer, connector, stun, route, peer-center,
vpn-portal, proxy, acl stats, mapped-listener, stats
```

每个 CLI 都要**连接 easytier-core 的 RPC 端口**并等待响应。在弱路由器（MIPS/ARM 低端）上单个调用可能数百 ms，11 个串行 ⇒ **单次请求可能数秒**，而轮询间隔只有 5 s。

> **证据：本仓曾经有缓存设计但被绕过。**
> `root/etc/init.d/easytier:897-898` 的 `stop_service` 会清理：
> ```
> /tmp/easytier-cli_peer  /tmp/easytier-cli_connector  /tmp/easytier-cli_stun
> /tmp/easytier-cli_route /tmp/easytier-cli_acl        /tmp/easytier-cli_peer-center
> /tmp/easytier-cli_vpn-portal /tmp/easytier_cmd       /tmp/easytier-cli_node
> /tmp/easytier-cli_mapped_listener
> ```
> 但在 `root/usr/share/easytier/*.sh` 中 grep `easytier-cli_` / `cache` **无任何命中** —— 说明缓存实现已不存在（或从未落地），这些清理语句是**遗留物**，而控制器的直接调用**没有任何缓存**。

---

## 4. P3 — 日志页：2 秒全量拉取 + 全量 DOM 重建

**前端**：`luasrc/view/easytier/easytier_log.htm:698-705`

```js
pollTimer = setInterval(function() {
    if (autoRefreshEnabled) { refreshLog(); }
}, 2000);                      // ← 2 秒
```

`refreshLog()`（`:592-628`）：

```js
var rawLog = xhr.responseText || '';        // ← 整个日志文件
var lines = rawLog.split('\n');
var html = '';
for (var i = 0; i < lines.length; i++) {
    html += formatLogLine(lines[i]);        // ← 逐行字符串拼接
}
content.innerHTML = html;                   // ← 全量 DOM 重建
```

**后端**：`easytier.lua:356-365` `get_log()`

```lua
log = log .. luci.sys.exec("sed 's/\\x1b\\[[0-9;]*m//g' " .. file)
```

⇒ 对整个 `/tmp/easytier.log` 跑 `sed` 并**全量返回**。

**规模问题**：`root/etc/init.d/easytier:184-190` 的轮转阈值是 **5120 KB ≈ 5 MB**：

```sh
LOG_SIZE=$(ls -l /tmp/easytier.log | awk '{print int($5/1024)}')
if [ $LOG_SIZE -gt 5120 ]; then
    tail -n 500 /tmp/easytier.log > /tmp/easytier.log.tmp
    ...
```

⇒ 日志文件在轮转前可涨到 **5 MB**，而日志页**每 2 秒**完整拉取一次并重建整个 DOM。在开启自动刷新的情况下，这几乎必然让浏览器与路由器双双卡顿。

---

## 5. 与 RDP 卡顿的因果链（关键）

这是「Web 控制台」与「RDP 卡顿」直接相关的部分：

```
用户在 LuCI 打开状态页 / 连接信息页 / 日志页
        │
        ├─ 每 2~5 秒发起 HTTP 请求（若远程管理 ⇒ 流量经 EasyTier 隧道）
        │
        ├─ 路由器上派生大量进程（top ×2、curl、11× easytier-cli、sed）
        │        └─ 抢占 CPU ⇒ easytier-core 调度延迟 ↑
        │
        └─ 隧道内的突发流量涌入发送路径
                 └─ 环缓冲仅 128（可用 124），满即 force_send → BufferFull → 静默丢包
                          └─ 与 RDP 流竞争同一队列 ⇒ RDP 丢包 ⇒ 卡顿
```

**两个叠加放大因素**：

1. **若通过隧道远程访问 LuCI**，控制台自身的轮询流量（含 5 MB 日志）与 RDP 共享同一条 PeerConn。
2. **日志轮转阈值 5 MB 过大**，配合 2 秒全量拉取，单次交互就能产生数 MB 隧道流量。

> 该队列丢包机制见主仓 `docs/current/p2p-direct-throughput-audit.md` §3 B2 与 `p2p-direct-stability-audit.md` §3.5。

---

## 6. 其他已核实问题（非卡顿但相关）

| 项 | 位置 | 说明 |
|----|------|------|
| **启动即清空日志** | `init.d/easytier:830-831` | `echo "" > /tmp/easytier.log`；procd `respawn` 每次重启都会清空，排障时日志丢失 |
| **通断检测会重启服务** | `init.d/easytier:36` | `check()` 在指定 IP 全部 ping 不通时执行 `/etc/init.d/easytier restart` —— 网络抖动可能**触发连接重建**（对应主仓 S1「拆连接」问题），造成 RDP 闪断 |
| **CPU 解析方式脆弱** | `easytier.lua:99,107` | 用 `top -b -n1` + `awk` 匹配字段名；`top` 输出格式随 busybox 版本变化，且成本远高于直接读 `/proc/<pid>/stat` |
| **命令拼接执行** | `easytier.lua:246,263,272,279,361` 等 | 多处 `"df -h '" .. path .. "'"` 形式拼接后执行；`reset_database` 有路径校验（`:831-837`）但其它端点较松 —— **注入风险**，非性能问题但建议一并收敛 |
| **`save_web_config` 无校验** | `easytier.lua:739-813` | 30+ 个字段直接落 UCI，无端口/地址合法性校验 |

---

## 7. 建议修复（按性价比排序）

| 优先级 | 改动 | 目标 | 预期 | 状态 |
|--------|------|------|------|------|
| **1** | 状态页 `curl` **失败也写负缓存**（TTL 如 30 min），或把版本检查移出轮询 | P1 | 消除 3 秒 curl 循环，**单项即可显著缓解卡死** | ✅ 已实施（TTL 30 min，占位 `-`） |
| **2** | 日志页 `get_log` 支持 `Range` / `offset` 增量读取；前端改为**追加**而非重建 DOM；轮询间隔 2s → 5~10s | P3 | 消除 MB 级重复传输 | ✅ 已实施（tail 128 KB + `offset`，5s；轮转 1 MB） |
| **3** | 连接信息页恢复 **`/tmp/easytier-cli_*` 缓存**（对应 init.d 已有的清理逻辑），TTL 3~5 s | P2 | 11 进程/次 → 最多 11 进程/5s | ✅ 已实施（TTL 5 s） |
| **4** | 移除 `top`，改读 `/proc/<pid>/stat` + `/proc/<pid>/statm` | P1 | 去掉最昂贵的两次 `top` | ✅ 已实施（`/proc/<pid>/stat` + `status`，CPU 为均值近似） |
| **5** | `updateTunInterface` 降频（如每 3 次轮询一次），或与主状态合并为一个请求 | P1 | 请求数减半 | ✅ 已实施（每 2 次轮询一次） |
| **6** | 日志轮转阈值 5120 KB → 512 KB~1 MB | P3 | 限制单次传输上界 | ✅ 已实施（1024 KB，core×2 + web） |
| **7** | 状态页轮询间隔 3 s → 5~10 s | P1 | 直接降低基线负载 | ✅ 已实施（5 s） |
| 8 | `check()` 增加退避与重启限频（避免网络抖动反复重启服务） | §6 | 减少非预期连接重建 | ⬜ 未做（超出本次范围） |

---

## 8. 局限

1. **未在真实 OpenWrt 设备上 profiling**：以上基于代码审读；各操作的实际耗时依设备性能（MIPS/ARM 差异大）而变。
2. 未覆盖 `easytier_web.htm`（内嵌 ET Web 控制台页面，仅确认其用 `setInterval(checkWebStatus, 10000)`，10 s 一次状态检查，未深入）。
3. 未覆盖 `easytier_upload.htm` / `easytier_config`（CBI 表单页，非轮询页）。
4. 命令注入项仅记录现象，未做完整安全审计。
5. 结论基于 `version.mk` 标注的 **2.7.5**；与主仓审查所用的 2.7.6 存在版本差，但本节所涉文件逻辑一致。
