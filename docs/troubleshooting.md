# 部署与排错说明

部署完成后的运行形态：

- `/usr/bin/portal_login.sh` —— 探测式登录脚本（核心逻辑）
- `/etc/init.d/portal` —— procd 守护服务（开机自启, 每 60 秒检测, 掉线自动重登）
- `/etc/portal.conf` —— 配置文件（账号密码等, 权限 600, 不随脚本升级被覆盖）

已在本校环境下完成端到端验证：注销会话 → 脚本 3 秒内自动重登成功 → 外网恢复访问。

脚本为纯 POSIX Shell，不依赖路由器型号、CPU 架构或 WAN 接口名，任意满足 [README 环境要求](../README.md#环境要求) 的 OpenWrt 均可部署。

## 方案架构（探测式）

脚本不依赖任何接口名/IP/MAC/vlan 配置，全部动态获取：

1. **在线探测**：`curl http://www.baidu.com/`
   - 在线 → 返回百度真实页面 → 跳过
   - 未认证 → AC(MAGI设备) 拦截，返回 `location.replace("http://<portal>/portal.do?...")` 跳转页
   - 从跳转 URL 中自动获取真实 `wlanuserip / mac / vlan / hostname / rand`
2. GET 登录页提取 `randstr`（保存 JSESSIONID Cookie）
3. POST 63 字段到 `/portalAuthAction.do`（带 Cookie/Referer，MAC 冒号转义 `%3A`）
4. 再探测验证是否在线（实测认证**即时生效**，POST 后 3 秒即可确认）
5. 失败重试 3 次（每次重新取 randstr）

## 日常维护

```sh
logread | grep portal | tail      # 查看认证日志
/etc/init.d/portal restart        # 重启守护
/etc/init.d/portal stop           # 停止
vi /etc/portal.conf               # 改账号/参数(改完 restart 生效)
```

## 日志对照

| 日志 | 含义 |
|---|---|
| `在线, 跳过认证` | 正常心跳 |
| `开始认证: IP=... MAC=... VLAN=...` | 检测到掉线，开始登录 |
| `OK: 第 N 次认证成功, 网络已通` | 重登成功 |
| `ERROR: 账号未配置...` | 占位符未替换，按 README 填写 `/etc/portal.conf` |
| `ERROR: 探测无响应(外网未连接或断路)` | WAN 断路（网线/无线断开），下轮自动重试 |
| `ERROR: 3 次认证均失败` | 凭据或 Portal 侧问题，看 WARN 行上下文 |

## 升级与固件刷新

- **升级脚本**：重新上传后在项目目录执行 `sh install.sh`，`/etc/portal.conf` 不会被覆盖（旧脚本会自动备份为 `.old`）。
- **sysupgrade 刷机**：`/etc/config`、`/etc/portal.conf` 等不会默认保留，执行下面命令把配置加入保留列表：
  ```sh
  echo /etc/portal.conf >> /etc/sysupgrade.conf
  ```
  `/usr/bin/portal_login.sh` 与 `/etc/init.d/portal` 刷机后需重新部署（重跑 `install.sh` 即可）。

## 替代部署：无 procd 环境用 crontab

极老版本或特殊裁剪的固件若没有 procd，可改用系统 cron：

```sh
/etc/init.d/cron enable && /etc/init.d/cron start
echo '*/3 * * * * /usr/bin/portal_login.sh' >> /etc/crontabs/root
/etc/init.d/cron restart
```

> 建议用 `*/3`（每 3 分钟）而非每分钟：脚本单轮认证最多耗时约 2 分钟，间隔过短可能出现上一轮未结束、下一轮又启动的情况（在线时脚本数秒即退出，正常情况下无影响）。

## 常见问题

- **换了上网方式（有线 ↔ 无线中继 ↔ 手机 USB 共享）**：脚本无需任何修改，参数全部动态获取。拔掉 USB 共享后默认路由切回校园网 WAN 时，守护服务会自动完成首次认证。
- **一直认证失败**：先在浏览器手动登录一次确认凭据有效；再检查 `/etc/portal.conf` 中账号是否填写正确（注意行内引号需保留）。
- **安装 curl 失败**：未认证时路由器无法访问软件源——可先在任意设备手动完成一次网页认证，或临时用手机 USB 共享给路由器联网，再执行 `opkg install curl`。
- **4MB 闪存设备装不下 curl**：`df -h /overlay` 查看剩余空间；空间不足时可换用自带 curl 的固件，或使用外置存储/overlay 扩容方案。
- **`/tmp` 下的项目文件夹重启后消失**：正常，`/tmp` 是内存盘；`install.sh` 已把文件部署到持久位置，`/tmp` 里的副本可以删掉。

## 安全说明

- 密码为**明文**存储于 `/etc/portal.conf`（权限 600；若直接写在脚本里则请对脚本执行 `chmod 600`）。该 Portal 系统本身即明文提交密码，无法在客户端侧加密。
- 请勿把填入真实凭据的配置文件或脚本上传回仓库、截图或分享给他人。
