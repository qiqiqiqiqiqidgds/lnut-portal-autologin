#!/bin/sh
# Portal自动登录脚本（探测式·实测版） - 辽宁工业大学校园网 (深信服/Itellin Portal)
#
# 实测结论(2026-08):
#   - 未认证时访问任意HTTP站点, AC(MAGI设备)会拦截并返回 location.replace 跳转页,
#     跳转URL中携带真实参数: wlanuserip/mac/vlan(有线为大数值且非固定!)/hostname/rand
#   - 认证成功后同一URL返回真实响应(如阿里DNS 404页)
#   - 本校园网 ping 114.114.114.114 即使在线也不通, 不能用ping判定, 必须用HTTP探测
#   - 认证响应为GBK的HTML, 不可靠; 以HTTP探测结果为准
#   - POST需复用GET登录页的JSESSIONID Cookie, MAC冒号需转义为%3A
#
# 本脚本不依赖接口名/IP/MAC配置: 全部参数从拦截跳转URL动态获取,
# 有线WAN和无线中继均适用, 也无需知道当前vlan值。
# ========================================

# ===== 配置区(默认值) =====
# 两种配置方式(二选一, 详见 README「填写你的账号密码」):
#   推荐: 把账号写进 /etc/portal.conf(模板见 portal.conf.example), 升级脚本不丢配置
#   简单: 直接改下面两行(升级脚本前记得自行备份本文件)
USERID="YOUR_STUDENT_ID"      # <-- 学号
PASSWD="YOUR_PASSWORD"        # <-- 密码(明文; 该Portal的setMD5Passwd()实际未加密)

# 以下为辽宁工业大学环境默认参数, 本校用户无需修改; 外校用户请抓包后修改(见 docs/protocol-analysis.md)
PORTAL_IP="10.9.18.71"        # Portal服务器地址
AC_NAME="NFV-BASE"            # AC名称
AC_IP="10.9.11.145"           # AC IP
AUTH_KEY="itellin"            # 认证密钥
REDIR_URL="http%3A%2F%2Fwww.sina.com.cn%2F"   # 认证后跳转目标(URL编码后)

PROBE_URL="http://www.baidu.com/" # 在线探测目标(域名+DNS方式; 223.5.5.5等IP实测不稳定, ping 114在本校园网在线也不通, 均不可用)
COOKIE_FILE="/tmp/portal.cookie"
LOG_TAG="portal"
MAX_RETRY=3
# =================

# /etc/portal.conf 存在则覆盖上面的默认值(推荐的配置方式)
[ -r /etc/portal.conf ] && . /etc/portal.conf

log() { logger -t "$LOG_TAG" "$1"; }

# 账号尚未配置时直接退出, 避免发起无意义的认证请求
case "$USERID$PASSWD" in
    ""|*YOUR_STUDENT_ID*|*你的学号*|*YOUR_PASSWORD*|*你的密码*)
        log "ERROR: 账号未配置, 请编辑 /etc/portal.conf 或本脚本配置区(方法见 README)"
        exit 1
        ;;
esac

if ! command -v curl >/dev/null 2>&1; then
    log "ERROR: 未安装 curl, 请执行 opkg install curl"
    exit 1
fi

# ---- HTTP 探测: 在线返回百度真实页面; 未认证返回含 location.replace 的AC拦截页 ----
# (实测认证生效为即时, POST后3秒即可探测到在线)
# 超时12秒并在空响应时重试一次, 兼容DNS服务器切换瞬间(如手机USB共享拔出后)
probe() { curl -s -m 12 "$PROBE_URL"; }
probe2() {
    local b
    b=$(probe)
    [ -z "$b" ] && sleep 3 && b=$(probe)
    echo "$b"
}

# ---- 在线检测 ----
BODY=$(probe2)
if [ -z "$BODY" ]; then
    log "ERROR: 探测无响应(外网未连接或断路), 本轮放弃"
    exit 1
fi
if ! echo "$BODY" | grep -q "location.replace"; then
    log "在线, 跳过认证"
    exit 0
fi

# ---- 从拦截页提取真实登录URL(含正确的 wlanuserip/mac/vlan/hostname/rand) ----
LOGIN_URL=$(echo "$BODY" | sed -n 's/.*location.replace("\([^"]*\)").*/\1/p' | head -1)
if [ -z "$LOGIN_URL" ]; then
    log "ERROR: 拦截页中未找到跳转URL"
    exit 1
fi

# 从登录URL解析动态参数
WLANUSERIP=$(echo "$LOGIN_URL" | sed -n 's/.*wlanuserip=\([0-9.]*\).*/\1/p')
WAN_MAC=$(echo "$LOGIN_URL" | sed -n 's/.*mac=\([0-9a-f:]*\).*/\1/p')
VLAN=$(echo "$LOGIN_URL" | sed -n 's/.*vlan=\([0-9]*\).*/\1/p')
[ -z "$VLAN" ] && VLAN=0
MAC_ENC=$(echo "$WAN_MAC" | sed 's/:/%3A/g')
log "开始认证: IP=$WLANUSERIP MAC=$WAN_MAC VLAN=$VLAN"

RETRY=0
while [ $RETRY -lt $MAX_RETRY ]; do
    RETRY=$((RETRY + 1))

    # GET 登录页: 提取 randstr 并保存 JSESSIONID Cookie
    PAGE=$(curl -s -m 10 -c "$COOKIE_FILE" "$LOGIN_URL")
    RANDSTR=$(echo "$PAGE" | grep -a "randstr" | sed -n "s/.*value=['\"]\([^'\"]*\)['\"].*/\1/p" | head -1)
    if [ -z "$RANDSTR" ]; then
        log "WARN: 第 $RETRY 次未取到 randstr, 重试"
        sleep $((RETRY * 3))
        continue
    fi

    # POST 认证: 完整复刻浏览器提交的63字段, 动态项为 IP/MAC/vlan/randstr/账号/密码
    POST_DATA="wlanuserip=$WLANUSERIP&wlanacname=$AC_NAME&chal_id=&chal_vector=&auth_type=PAP&seq_id=&req_id=&wlanacIp=$AC_IP&ssid=&vlan=$VLAN&mac=$MAC_ENC&message=&bank_acct=&isCookies=&version=0&authkey=$AUTH_KEY&url=$REDIR_URL&usertime=0&listpasscode=0&listgetpass=0&getpasstype=0&randstr=$RANDSTR&domain=&isRadiusProxy=false&usertype=0&isHaveNotice=0&times=12&weizhi=0&smsid=&freeuser=&freepasswd=&listwxauth=0&templatetype=1&tname=1&logintype=0&act=&is189=false&terminalType=&checkterminal=true&portalpageid=1&listfreeauth=0&viewlogin=1&userid=$USERID&wisprpasswd=&twocode=&authGroupId=&alipayappid=&wlanstalocation=&wlanstamac=&wlanstaos=&wlanstahardtype=&smsoperatorsflat=&reason=&res=&userurl=&challenge=&uamip=&uamport=&toqrcode=&isIOSPortal=false&useridtemp=$USERID&passwd=$PASSWD&wxuser="

    curl -s -m 10 -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
        -e "$LOGIN_URL" \
        -H "Origin: http://$PORTAL_IP" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36" \
        -d "$POST_DATA" \
        "http://$PORTAL_IP/portalAuthAction.do" -o /dev/null

    # 响应为GBK HTML不可靠, 以HTTP探测判定是否真正在线
    sleep 3
    BODY=$(probe2)
    if [ -n "$BODY" ] && ! echo "$BODY" | grep -q "location.replace"; then
        log "OK: 第 $RETRY 次认证成功, 网络已通"
        rm -f "$COOKIE_FILE"
        exit 0
    fi

    log "WARN: 第 $RETRY 次认证后仍不在线, 重试"
    sleep $((RETRY * 5))
done

# 重试间隔递增, 单轮最多约2分钟; 由守护服务下一周期继续

log "ERROR: $MAX_RETRY 次认证均失败"
rm -f "$COOKIE_FILE"
exit 1
