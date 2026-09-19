# Portal 认证协议分析（辽宁工业大学 · 深信服/Itellin）

本文档是逆向分析校园网 Portal 认证页面（`portal/portal_new.js`）与浏览器抓包得到的协议细节，
是 `portal_login.sh` 的实现依据。**想适配其他学校的读者**，可以按本文末尾的方法自行抓包对照修改。

> 说明：文中所有涉及个人凭据的值（学号、密码、MAC、IP）均已替换为占位符。

## 1. 认证系统信息

| 项目 | 值 |
|---|---|
| 认证系统 | 深信服 / Itellin Portal |
| Portal 服务器 | `http://10.9.18.71/`（`portal.do` 登录页, `portalAuthAction.do` 提交接口） |
| AC 名称 | `NFV-BASE` |
| AC IP | `10.9.11.145` |
| authkey | `itellin` |
| 服务端 | Apache/2.4.4 (Unix) + mod_jk/1.2.37 |
| 会话机制 | JSESSIONID Cookie（POST 前必须先 GET 登录页拿到） |
| 响应编码 | GBK 的 HTML / alert 脚本，不适合做文本匹配判定 |

## 2. 认证流程

```
未认证时访问任意 HTTP 站点
  └─ AC 拦截, 返回含 location.replace("...portal.do?...") 的跳转页
       └─ 跳转 URL 携带真实参数: wlanuserip / mac / vlan / hostname / rand
            └─ GET 登录页 → 提取隐藏字段 randstr + 保存 JSESSIONID Cookie
                 └─ POST 63 个字段到 /portalAuthAction.do
                      └─ 认证即时生效, 再做一次 HTTP 探测确认在线
```

登录页 URL 形如：

```
http://10.9.18.71/portal.do?wlanuserip=<你的内网IP>&wlanacname=NFV-BASE&mac=<你的MAC>&vlan=<动态值>&hostname=&rand=<随机串>&url=http://www.sina.com.cn/
```

## 3. 登录页表单结构（portal_new.js）

表单：`<form action="/portalAuthAction.do" method="POST" onsubmit="return setMD5Passwd();" name="portalForm">`

**隐藏字段（各校可能不同，抓包为准）：**

| 字段 | 值 | 字段 | 值 |
|---|---|---|---|
| wlanuserip | 动态(WAN IP) | wlanacname | NFV-BASE |
| auth_type | PAP | wlanacIp | 10.9.11.145 |
| mac | 动态(WAN MAC) | authkey | itellin |
| randstr | 登录页随机串 | vlan | 动态(拦截URL中取) |
| version | 0 | url | http://www.sina.com.cn/ |
| usertype | 0 | templatetype | 1 |
| tname | 1 | logintype | 0 |
| times | 12 | weizhi | 0 |
| isRadiusProxy | false | is189 | false |
| checkterminal | true | portalpageid | 1 |
| listfreeauth | 0 | viewlogin | 1 |
| listwxauth / listpasscode / listgetpass / getpasstype / isHaveNotice | 0 | chal_id / chal_vector / seq_id / req_id / ssid / message / bank_acct / isCookies / domain / smsid / freeuser / freepasswd / act / terminalType / wisprpasswd / twocode / authGroupId | (空) |

**用户输入字段：**

- `useridtemp` —— 学号（可见文本框, POST 时同时填到 `userid`）
- `passwd` —— 密码（密码框）

### setMD5Passwd() 的关键发现

函数名含 "MD5"，但实际代码**没有执行任何 MD5 计算**——仅做表单非空校验后 `return true`，密码以明文提交。因此脚本无需实现任何哈希。

## 4. POST 请求要点（实测）

- 完整复刻浏览器提交的 **63 个字段**（脚本 `POST_DATA` 一行即为此串）
- 必须携带 GET 登录页时获得的 `JSESSIONID` Cookie
- MAC 中的冒号需 URL 编码为 `%3A`（如 `AA%3ABB%3A...`）
- `Referer` 设为登录页 URL；`Origin` 设为 Portal 站点
- 实测服务端**不校验** Referer/Origin/UA（带与不带响应字节级相同），脚本保留这些头仅为保险
- 认证失败返回 `alert('错误1002...')` 之类的 GBK HTML，**不能**靠响应文本判断成败，务必用 HTTP 探测复核

## 5. 抓包方法（适配其他学校用）

1. 断开认证（或换一台未认证设备），连上校园网
2. 浏览器按 `F12` 打开开发者工具 → Network 面板
3. 访问任意 `http://` 网站，会被劫持到 Portal 登录页
4. 手动输入账号密码登录一次
5. 在 Network 里找到提交表单的 POST 请求（本校园网为 `/portalAuthAction.do`）
6. 查看 **Payload（表单字段）** 和 **请求头**，对照本文第 3、4 节替换脚本中的：
   - `PORTAL_IP` / `AC_NAME` / `AC_IP` / `AUTH_KEY` / `REDIR_URL`
   - 拦截页特征串（本校园网为 `location.replace`）、登录页 `randstr` 的提取方式
7. 注意确认在线判定方式：**不要假设 ping 可用**（本校园网在线时 ping 114.114.114.114 也不通），用 HTTP 探测最稳

## 6. 已知坑（实测踩过的）

| 坑 | 说明 |
|---|---|
| vlan 不是 0 | 本校园网有线口 vlan 为大数值且动态变化，必须从拦截跳转 URL 中取；填 0 时认证"成功"但流量不通 |
| ping 判定在线不可靠 | 在线状态下 ping 公网 IP 也可能 100% 丢包 |
| 裸 IP 探测不可靠 | 同一时刻域名探测通、裸 IP 无响应，探测目标用域名 |
| 认证即时生效 | POST 后 3 秒探测即可确认，无需长等待 |
| 有线/无线同一套 Portal | 拦截跳转与服务端回显一致，脚本无需区分 |
