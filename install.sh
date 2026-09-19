#!/bin/sh
# install.sh —— 一键安装/卸载(在 OpenWrt 路由器上以 root 运行)
#
# 用法(在项目目录内执行):
#   sh install.sh               安装(账号已配置时自动启动服务)
#   sh install.sh --no-start    只安装不启动
#   sh install.sh --uninstall   卸载(保留 /etc/portal.conf 配置)
#
# 脚本可重复执行(幂等), 已存在的配置不会被覆盖。

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
BIN=/usr/bin/portal_login.sh
INIT=/etc/init.d/portal
CONF=/etc/portal.conf
ARG="${1:-}"

msg() { echo "[install] $*"; }
die() { echo "[install] 错误: $*" >&2; exit 1; }

# 检测指定文件中的账号是否仍为占位符或为空
unconfigured() {
    grep -q '^USERID="\("\|YOUR_STUDENT_ID\|你的学号\)"' "$1" 2>/dev/null && return 0
    grep -q '^PASSWD="\("\|YOUR_PASSWORD\|你的密码\)"' "$1" 2>/dev/null && return 0
    return 1
}

[ "$(id -u)" = "0" ] || die "请以 root 身份运行(ssh 登录 OpenWrt 默认即为 root)"

case "$ARG" in
    --uninstall)
        msg "停止并移除服务..."
        "$INIT" stop 2>/dev/null
        "$INIT" disable 2>/dev/null
        rm -f "$INIT" "$BIN" "$BIN.old"
        if [ -f "$CONF" ]; then
            msg "已保留 $CONF (其中含你的账号, 如需彻底删除请手动执行: rm $CONF)"
        fi
        msg "卸载完成"
        exit 0
        ;;
    ""|--no-start) ;;
    *) die "未知参数: $ARG (支持 --no-start / --uninstall)" ;;
esac

[ -f "$DIR/portal_login.sh" ] || die "当前目录未找到 portal_login.sh, 请在项目目录内执行"
[ -f "$DIR/portal.init" ] || die "当前目录未找到 portal.init, 请在项目目录内执行"

# 1. 依赖检查: curl(OpenWrt 默认不带, 需安装)
if ! command -v curl >/dev/null 2>&1; then
    msg "未检测到 curl, 尝试自动安装..."
    if command -v opkg >/dev/null 2>&1; then
        opkg update && opkg install curl \
            || die "curl 安装失败: 请先让路由器能访问软件源(可临时用手机 USB 共享网络, 或先在任意设备手动完成一次网页认证)后重试"
    else
        die "本固件无 opkg 且未安装 curl, 请手动安装 curl 或更换带完整软件源的 OpenWrt 固件"
    fi
fi

# 2. 部署文件(旧版脚本自动备份, 不覆盖已有配置)
if [ -f "$BIN" ]; then
    cp "$BIN" "$BIN.old"
    msg "已备份旧版脚本: $BIN.old"
fi
cp "$DIR/portal_login.sh" "$BIN"
cp "$DIR/portal.init" "$INIT"
chmod 755 "$BIN" "$INIT"

if [ ! -f "$CONF" ] && [ -f "$DIR/portal.conf.example" ]; then
    cp "$DIR/portal.conf.example" "$CONF"
    chmod 600 "$CONF"
    msg "已生成配置模板: $CONF"
fi

# 3. 设置开机自启
"$INIT" enable

# 4. 启动服务
if [ "$ARG" = "--no-start" ]; then
    msg "按要求未启动服务, 需要时执行: $INIT start"
elif [ -f "$CONF" ]; then
    if unconfigured "$CONF"; then
        msg "------------------------------------------------"
        msg "账号尚未配置! 请编辑配置文件:"
        msg "    vi $CONF"
        msg "把 USERID / PASSWD 两行的占位符改成你的学号和密码,"
        msg "保存后执行: $INIT start"
        msg "------------------------------------------------"
        exit 0
    fi
    "$INIT" restart
    msg "服务已启动"
else
    if unconfigured "$BIN"; then
        msg "账号尚未配置! 请编辑 $BIN 配置区的 USERID/PASSWD, 或复制 portal.conf.example 为 $CONF"
        exit 0
    fi
    "$INIT" restart
    msg "服务已启动"
fi

msg "安装完成。常用命令:"
msg "  vi $CONF                      修改账号/参数"
msg "  $INIT restart                 重启服务"
msg "  $INIT stop                    停止服务"
msg "  logread | grep portal | tail  查看认证日志"
