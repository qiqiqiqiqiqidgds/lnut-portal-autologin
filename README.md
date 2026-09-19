# 辽宁工业大学校园网 Portal 自动登录（OpenWrt）
### LNUT Campus-Network Portal Auto-Login for OpenWrt

[![Platform](https://img.shields.io/badge/platform-OpenWrt-blue)](https://openwrt.org/)
[![Shell](https://img.shields.io/badge/language-POSIX%20Shell-green)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

**[简体中文](#chinese)** | **[English](#english)**

---

<a id="chinese"></a>

在 OpenWrt 路由器上自动完成辽宁工业大学校园网（深信服 / Itellin Portal）的 Web 认证，**掉线自动重连、开机自动登录**，无需任何手动操作。

- **通用部署**：纯 POSIX Shell 脚本，不依赖路由器型号 / CPU 架构 / WAN 接口名，任意标准 OpenWrt 环境均可运行；提供一键安装脚本
- **探测式设计**：认证所需的 IP / MAC / VLAN 等参数全部从认证拦截页动态获取，有线 WAN 与无线中继通用，无需任何固定配置
- **可靠判定**：用 HTTP 探测而非 ping 判定在线（本校网络 ping 公网即使在线也不通），认证成功与否以实测为准
- **守护运行**：基于 procd 的开机自启服务，每 60 秒检测一次，掉线 3 秒内自动重登
- **配置外置**：账号写在独立的 `/etc/portal.conf`，升级脚本不丢配置（也支持直接改脚本）
- **协议完整复刻**：完整提交浏览器登录时的 63 个表单字段，实测端到端可用

> ⚠️ **本项目仅供学习交流**，请确认符合你所在学校的相关规定后再使用。校园网账号密码为个人重要凭据，使用本项目产生的任何后果由使用者自行承担。

## 工作原理

```
每 60 秒探测一次 http://www.baidu.com/
 ├─ 返回真实页面 ──────────────→ 已在线，跳过
 └─ 返回 AC 拦截跳转页 ────────→ 从跳转 URL 提取 wlanuserip/mac/vlan/rand
      └─ GET 登录页 → 取 randstr + JSESSIONID Cookie
           └─ POST 63 字段到 /portalAuthAction.do
                └─ 3 秒后再探测验证 → 未通则重试（最多 3 次）
```

协议细节与适配其他学校的方法见 [docs/protocol-analysis.md](docs/protocol-analysis.md)。

## 环境要求

| 项目 | 要求 | 说明 |
|---|---|---|
| 系统 | OpenWrt 18.06 及以上 | 需系统自带 busybox 与 procd（近年官方版本及 ImmortalWrt 等衍生固件均满足）；无 procd 的环境见[替代方案](docs/troubleshooting.md) |
| 软件依赖 | `curl` | OpenWrt 默认不自带，`install.sh` 会尝试自动 `opkg install curl`；其余用到的 `logger/sed/grep` 均为 busybox 内置 |
| 存储空间 | overlay 剩余 ≥ 2 MB | curl 及依赖约需 1 MB；4 MB 闪存的老设备可能装不下，可用 `df -h /overlay` 查看 |
| 网络环境 | WAN 口已获取 IPv4 地址 | DHCP / 静态 / 无线中继均可；认证参数自动获取，**无需**固定 IP / MAC / 接口名 |
| 执行权限 | root | ssh 登录 OpenWrt 默认即为 root |
| CPU 架构 | 无限制 | 纯 Shell 脚本，无二进制依赖 |
| LuCI | 非必需 | 纯命令行部署，不依赖 Web 管理界面 |

**已实测环境**：NIDEAYU-AX1800（OpenWrt，有线 WAN 与无线中继两种模式）。脚本按通用环境编写，未在你设备上实测过的组合如遇问题欢迎提 Issue。

**已知限制**：

- 仅适配深信服 / Itellin Portal（本校认证系统）；锐捷、Dr.COM 等其他系统需自行适配（方法见 [docs/protocol-analysis.md](docs/protocol-analysis.md)）
- IPv6-only 的 WAN 环境未测试
- 极精简的自编译固件若无 `logger`/`procd`，需自行补齐或改用 crontab 方式运行

## 文件结构

```
.
├── README.md               # 本文件
├── LICENSE                 # MIT 许可证
├── .gitignore
├── install.sh              # 一键安装/卸载脚本(在路由器上运行)
├── portal_login.sh         # 核心登录脚本
├── portal.init             # procd 守护服务
├── portal.conf.example     # 配置文件模板(复制为 /etc/portal.conf 使用)
└── docs/
    ├── protocol-analysis.md   # Portal 协议逆向分析(外校适配必读)
    └── troubleshooting.md     # 部署形态、日志对照、常见问题、替代部署方案
```

## 快速开始

### 方式 A：一键安装（推荐）

**第 1 步**：把整个项目文件夹上传到路由器 `/tmp`（把 `192.168.x.x` 换成你路由器的管理地址）：

```sh
scp -r lnut-portal-autologin root@192.168.x.x:/tmp/
```

Windows 用户可在 PowerShell 中执行同样的 `scp` 命令（系统自带），或用 WinSCP 上传。

**第 2 步**：ssh 登录路由器，执行安装：

```sh
cd /tmp/lnut-portal-autologin
sh install.sh
```

安装脚本会自动：检查并安装 curl → 部署文件到 `/usr/bin` 与 `/etc/init.d` → 生成配置文件 → 设置开机自启 →（账号已配置时）启动服务。可重复执行，不会覆盖已有配置。

**第 3 步**：按下一节填写账号密码，然后启动服务。

### 方式 B：手动安装

```sh
# 1. 上传文件
scp portal_login.sh root@192.168.x.x:/usr/bin/portal_login.sh
scp portal.init       root@192.168.x.x:/etc/init.d/portal

# 2. 在路由器上执行
opkg update && opkg install curl        # 依赖, 已安装可跳过
chmod 755 /usr/bin/portal_login.sh /etc/init.d/portal
cp /tmp/lnut-portal-autologin/portal.conf.example /etc/portal.conf   # 或自行上传模板
chmod 600 /etc/portal.conf
/etc/init.d/portal enable               # 开机自启
/etc/init.d/portal start                # 立即启动
```

## 填写你的账号密码 ⚠️ 必做

两种方式**二选一**：

### 方式一（推荐）：编辑配置文件 `/etc/portal.conf`

```sh
vi /etc/portal.conf
```

把**第 7、8 行**的占位符改成你的账号：

```sh
USERID="你的学号"     # <-- 改成你的学号(即平时在校园网登录页输入的账号)
PASSWD="你的密码"     # <-- 改成你的校园网密码
```

> 📌 配置与脚本分离：以后升级脚本无需重新填写；建议再执行
> `echo /etc/portal.conf >> /etc/sysupgrade.conf`，刷机升级固件后配置也会自动保留。

### 方式二：直接改脚本

```sh
vi /usr/bin/portal_login.sh
```

修改配置区第 **20、21 行**（`# ===== 配置区(默认值) =====` 下方的 `USERID=` / `PASSWD=`，带 `<--` 注释标记）。注意升级脚本时改动会被覆盖，需自行备份。

填写并保存后（重新）启动服务：

```sh
/etc/init.d/portal restart
```

> 🔒 密码为**明文**存储（该 Portal 前端本身即明文提交，无法在客户端侧加密），请确保 `/etc/portal.conf` 权限为 600（install.sh 已自动设置）。

## 配置项总览

全部配置集中在 `/etc/portal.conf`（或脚本配置区），**辽宁工业大学用户只需填写 `USERID` / `PASSWD` 两项**：

| 变量 | 说明 | 是否需要改 |
|---|---|---|
| `USERID` | **你的学号**（conf 第 7 行 / 脚本第 20 行） | ✅ **必填** |
| `PASSWD` | **你的校园网密码**（conf 第 8 行 / 脚本第 21 行） | ✅ **必填** |
| `PORTAL_IP` | Portal 服务器地址，默认 `10.9.18.71` | 本校不用改 |
| `AC_NAME` | AC 名称，默认 `NFV-BASE` | 本校不用改 |
| `AC_IP` | AC 地址，默认 `10.9.11.145` | 本校不用改 |
| `AUTH_KEY` | 认证密钥，默认 `itellin` | 本校不用改 |
| `REDIR_URL` | 认证后跳转目标（URL 编码） | 一般不用改 |
| `PROBE_URL` | 在线探测目标，默认百度（建议用域名） | 一般不用改 |
| `MAX_RETRY` | 单轮认证重试次数，默认 3 | 一般不用改 |
| `INTERVAL` | 检测周期（秒），默认 60 | 一般不用改 |

**其他学校用户**：除账号密码外，还需按你自己抓包的结果修改 `PORTAL_IP` / `AC_NAME` / `AC_IP` / `AUTH_KEY`，并可能需要调整拦截页特征与字段提取逻辑，详见 [docs/protocol-analysis.md](docs/protocol-analysis.md)（内含 F12 抓包教程）。

## 验证与排错

```sh
logread | grep portal | tail      # 查看认证日志
```

| 日志 | 含义 |
|---|---|
| `在线, 跳过认证` | 正常心跳 |
| `开始认证: IP=... MAC=... VLAN=...` | 检测到掉线，开始登录 |
| `OK: 第 N 次认证成功, 网络已通` | 重登成功 |
| `ERROR: 账号未配置...` | 占位符未替换，按上一节填写 |
| `ERROR: 探测无响应(外网未连接或断路)` | WAN 断路，下轮自动重试 |
| `ERROR: 3 次认证均失败` | 多为凭据错误或 Portal 侧问题 |

更多内容（日志详解、常见问题、无 procd 环境的 crontab 部署、固件升级注意事项）见 [docs/troubleshooting.md](docs/troubleshooting.md)。

## 卸载

```sh
cd /tmp/lnut-portal-autologin
sh install.sh --uninstall          # 停止并移除服务, 保留 /etc/portal.conf
rm -f /etc/portal.conf             # (可选) 彻底删除含账号的配置
```

## 🔒 安全提示

- 校园网密码会**明文**存放在路由器上（该 Portal 前端本身即明文提交，无法客户端加密）。请务必：
  - 保持 `/etc/portal.conf` 权限为 600（install.sh 已自动设置）
  - 修改路由器默认管理密码
  - **不要**把填了真实账号的配置文件或脚本提交回本仓库或对外分享
- 本脚本仅在路由器本机与校园网 Portal 之间通信，不涉及任何第三方服务器。

## 适配其他学校

本项目针对辽宁工业大学（深信服 / Itellin Portal）编写，但认证流程在国内高校中较为通用。适配步骤：

1. 按 [docs/protocol-analysis.md](docs/protocol-analysis.md) 第 5 节的方法用浏览器 F12 抓包
2. 在 `/etc/portal.conf` 中修改 `PORTAL_IP` / `AC_NAME` / `AC_IP` / `AUTH_KEY`
3. 检查拦截页特征（`location.replace`）与 `randstr` 提取方式是否一致
4. 欢迎提 Issue / PR 反馈适配结果

## License

[MIT](./LICENSE) —— 可自由使用、修改和分发，请保留许可证声明。

---

<a id="english"></a>

Automatically completes the web authentication of the **Liaoning University of Technology (LNUT) campus network** (Sangfor / Itellin portal) on an OpenWrt router — **auto re-login on disconnect, auto login at boot**, no manual action required.

> 📖 The two documents under `docs/` are written in Chinese; the essential deployment and troubleshooting information is covered below.

- **Generic deployment** — pure POSIX shell; no dependency on router model, CPU architecture, or WAN interface name; runs on any standard OpenWrt; one-line installer included
- **Probe-based design** — all authentication parameters (IP / MAC / VLAN …) are extracted dynamically from the captive portal intercept page; works for both wired WAN and wireless relay
- **Reliable detection** — online status is determined by HTTP probing instead of ping (on this campus network ping to public IPs fails even when online); success is verified by re-probing, not by parsing responses
- **Supervised service** — procd-based service, enabled at boot, checks every 60 s, re-login within ~3 s of a drop
- **External configuration** — credentials live in a separate `/etc/portal.conf`; editing the script itself is also supported
- **Faithful protocol replication** — submits the full 63 form fields exactly as the browser does; verified end-to-end

> ⚠️ **For study and educational purposes only.** Make sure this complies with your institution's policies before use. Your campus-network credentials are sensitive; you are responsible for how you use this project.

## How It Works

```
Probe http://www.baidu.com/ every 60 s
 ├─ Real page returned ─────────→ already online, skip
 └─ AC intercept page returned ─→ extract wlanuserip/mac/vlan/rand from the redirect URL
      └─ GET login page → obtain randstr + JSESSIONID cookie
           └─ POST 63 fields to /portalAuthAction.do
                └─ re-probe after 3 s to verify → retry up to 3 times if still offline
```

Protocol details: [docs/protocol-analysis.md](docs/protocol-analysis.md) (Chinese).

## Requirements

| Item | Requirement | Notes |
|---|---|---|
| System | OpenWrt 18.06+ | Requires busybox and procd (recent official releases and derivatives such as ImmortalWrt qualify); see [docs/troubleshooting.md](docs/troubleshooting.md) for a crontab alternative without procd |
| Software | `curl` | Not bundled with OpenWrt by default; `install.sh` tries `opkg install curl` automatically. All other commands used (`logger/sed/grep`) are busybox built-ins |
| Storage | ≥ 2 MB free overlay | curl and its dependencies need ~1 MB; may not fit on 4 MB-flash devices — check with `df -h /overlay` |
| Network | WAN has an IPv4 address | DHCP / static / wireless relay all work; all auth parameters are obtained dynamically — **no** fixed IP / MAC / interface needed |
| Privilege | root | The default ssh login on OpenWrt |
| CPU arch | Any | Pure shell script, no binary dependencies |
| LuCI | Not required | Fully command-line deployable |

**Tested on**: NIDEAYU-AX1800 (OpenWrt, both wired WAN and wireless relay modes). The script is written for generic environments — if you hit issues on an untested combination, please open an Issue.

**Known limitations**:

- Only supports the Sangfor / Itellin portal (the system used at LNUT); Ruijie, Dr.COM and other systems require adaptation (see docs, Chinese)
- IPv6-only WAN has not been tested
- Minimal self-built firmware lacking `logger`/`procd` needs them installed, or use the crontab alternative

## Repository Layout

```
.
├── README.md               # this file
├── LICENSE                 # MIT
├── .gitignore
├── install.sh              # one-line install/uninstall (run on the router)
├── portal_login.sh         # core login script
├── portal.init             # procd daemon service
├── portal.conf.example     # config template (copy to /etc/portal.conf)
└── docs/                   # protocol analysis & troubleshooting (Chinese)
```

## Quick Start

### Option A: one-line installer (recommended)

**Step 1** — upload the whole project folder to the router's `/tmp` (replace `192.168.x.x` with your router's address):

```sh
scp -r lnut-portal-autologin root@192.168.x.x:/tmp/
```

On Windows, run the same `scp` command in PowerShell (bundled with the OS) or use WinSCP.

**Step 2** — ssh into the router and run:

```sh
cd /tmp/lnut-portal-autologin
sh install.sh
```

The installer automatically: checks/installs curl → deploys files to `/usr/bin` and `/etc/init.d` → generates the config file → enables the boot service → starts it (if credentials are configured). It is idempotent and never overwrites an existing config.

**Step 3** — fill in your credentials (next section), then start the service.

### Option B: manual installation

```sh
# 1. Upload the files
scp portal_login.sh root@192.168.x.x:/usr/bin/portal_login.sh
scp portal.init       root@192.168.x.x:/etc/init.d/portal

# 2. On the router
opkg update && opkg install curl        # dependency; skip if present
chmod 755 /usr/bin/portal_login.sh /etc/init.d/portal
cp /tmp/lnut-portal-autologin/portal.conf.example /etc/portal.conf   # or upload the template yourself
chmod 600 /etc/portal.conf
/etc/init.d/portal enable               # start at boot
/etc/init.d/portal start                # start now
```

## Fill In Your Credentials ⚠️ Required

Choose **one** of the two ways:

### Method 1 (recommended): edit `/etc/portal.conf`

```sh
vi /etc/portal.conf
```

Replace the placeholders on **lines 7–8**:

```sh
USERID="你的学号"     # your student ID (the account you type on the campus login page)
PASSWD="你的密码"     # your campus-network password
```

> 📌 Keeping credentials separate from the script means upgrades never wipe your config. Recommended:
> `echo /etc/portal.conf >> /etc/sysupgrade.conf` so the file also survives firmware upgrades (sysupgrade).

### Method 2: edit the script directly

```sh
vi /usr/bin/portal_login.sh
```

Change `USERID=` / `PASSWD=` on **lines 20–21** (the two lines marked with `<--` in the config block at the top). Note that an upgrade will overwrite them — back them up yourself.

After saving, (re)start the service:

```sh
/etc/init.d/portal restart
```

> 🔒 The password is stored in **plaintext** (the portal frontend itself submits it in plaintext, so client-side encryption is impossible). Keep `/etc/portal.conf` at permission 600 (set automatically by install.sh).

## Configuration Reference

All options live in `/etc/portal.conf` (or the script's config block). **LNUT users only need to set `USERID` / `PASSWD`:**

| Variable | Description | Change needed? |
|---|---|---|
| `USERID` | **Your student ID** (conf line 7 / script line 20) | ✅ **required** |
| `PASSWD` | **Your campus-network password** (conf line 8 / script line 21) | ✅ **required** |
| `PORTAL_IP` | Portal server, default `10.9.18.71` | not for LNUT |
| `AC_NAME` | AC name, default `NFV-BASE` | not for LNUT |
| `AC_IP` | AC address, default `10.9.11.145` | not for LNUT |
| `AUTH_KEY` | Auth key, default `itellin` | not for LNUT |
| `REDIR_URL` | Post-auth redirect target (URL-encoded) | usually no |
| `PROBE_URL` | Online-probe target, default Baidu (a domain is recommended) | usually no |
| `MAX_RETRY` | Login retries per cycle, default 3 | usually no |
| `INTERVAL` | Check interval in seconds, default 60 | usually no |

**For other universities**: besides credentials, adjust `PORTAL_IP` / `AC_NAME` / `AC_IP` / `AUTH_KEY` from your own packet capture, and possibly the intercept-page pattern and field extraction — see [docs/protocol-analysis.md](docs/protocol-analysis.md) (Chinese, includes an F12 capture tutorial).

## Verification & Troubleshooting

```sh
logread | grep portal | tail      # view auth logs
```

| Log line | Meaning |
|---|---|
| `在线, 跳过认证` | Online heartbeat, normal |
| `开始认证: IP=... MAC=... VLAN=...` | Drop detected, logging in |
| `OK: 第 N 次认证成功, 网络已通` | Re-login succeeded |
| `ERROR: 账号未配置...` | Credentials not configured yet |
| `ERROR: 探测无响应(外网未连接或断路)` | WAN is down; retried next cycle |
| `ERROR: 3 次认证均失败` | Usually wrong credentials or a portal-side issue |

More (log reference, FAQ, crontab deployment for non-procd systems, firmware-upgrade notes): [docs/troubleshooting.md](docs/troubleshooting.md) (Chinese).

## Uninstall

```sh
cd /tmp/lnut-portal-autologin
sh install.sh --uninstall          # stop & remove the service, keep /etc/portal.conf
rm -f /etc/portal.conf             # (optional) remove the config containing your credentials
```

## 🔒 Security Notes

- Your password is stored **in plaintext** on the router (the portal itself submits it in plaintext; client-side encryption is not possible). Be sure to:
  - keep `/etc/portal.conf` at permission 600 (set automatically by install.sh)
  - change the router's default admin password
  - **never** commit or share a config/script containing real credentials
- The script only talks to the campus portal from the router itself — no third-party servers involved.

## Adapting to Other Universities

Written for LNUT (Sangfor / Itellin portal), but the flow is common among Chinese universities:

1. Capture your own login request with the browser's F12 tools (see docs, Chinese, §5)
2. Override `PORTAL_IP` / `AC_NAME` / `AC_IP` / `AUTH_KEY` in `/etc/portal.conf`
3. Check the intercept-page pattern (`location.replace`) and `randstr` extraction
4. Feedback via Issues / PRs is welcome

## License

[MIT](./LICENSE) — free to use, modify and distribute; keep the license notice.
