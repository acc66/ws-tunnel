#!/bin/bash
#================================================================
# gotcp-filter 一键安装 / 管理脚本（A 服务器）
# 用法: bash gotcp.sh            # 交互菜单
#       bash gotcp.sh install | addport 端口 | delport 端口 | ports
#                     log | restart | stop | status | target ip:port | update | uninstall
#================================================================

REPO="acc66/ws-tunnel"
BIN="/usr/local/bin/gotcp-filter"
CONF_DIR="/etc/gotcp"
CONF="$CONF_DIR/gotcp.conf"
SERVICE="gotcp-filter"
UNIT="/etc/systemd/system/${SERVICE}.service"
REDIS_ENV="/etc/haproxy/blacklist.env"

red()   { echo -e "\033[31m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
yellow(){ echo -e "\033[33m$*\033[0m"; }

[ "$(id -u)" -ne 0 ] && { red "请用 root 运行"; exit 1; }

load_conf() {
    LISTEN=":20001"; TARGET=""; VPATH="/mm"; ALLOW=""; EXTRA=""
    [ -f "$CONF" ] && . "$CONF"
}

save_conf() {
    mkdir -p "$CONF_DIR"
    cat > "$CONF" <<EOF
# 修改后执行: bash gotcp.sh restart
LISTEN="$LISTEN"
TARGET="$TARGET"
VPATH="$VPATH"
ALLOW="$ALLOW"
EXTRA="$EXTRA"
EOF
    chmod 600 "$CONF"
}

write_unit() {
    cat > "$UNIT" <<EOF
[Unit]
Description=gotcp-filter TCP relay with anti-probe blacklist
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
EnvironmentFile=$CONF
ExecStart=/bin/sh -c 'exec $BIN -listen "\$LISTEN" -target "\$TARGET" -path "\$VPATH" -allow "\$ALLOW" -env $REDIS_ENV \$EXTRA'
Restart=always
RestartSec=3
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

download_bin() {
    local arch
    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) red "不支持的架构: $(uname -m)"; exit 1 ;;
    esac
    local url="https://github.com/${REPO}/releases/latest/download/gotcp-filter-linux-${arch}"
    yellow "下载 $url"
    if ! curl -fL --connect-timeout 15 -o "${BIN}.new" "$url"; then
        red "下载失败（检查网络或 Release 是否已生成）"; rm -f "${BIN}.new"; exit 1
    fi
    chmod +x "${BIN}.new" && mv -f "${BIN}.new" "$BIN"
    green "已安装 $BIN"
}

valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

do_install() {
    command -v curl >/dev/null || { apt-get install -y curl 2>/dev/null || yum install -y curl; }
    load_conf
    read -rp "B 服务器地址 ip:port [${TARGET:-无}]: " t; [ -n "$t" ] && TARGET="$t"
    [ -z "$TARGET" ] && { red "必须填写 B 服务器地址"; exit 1; }
    read -rp "监听端口(逗号分隔) [${LISTEN//:/}]: " p
    if [ -n "$p" ]; then
        LISTEN=""
        for x in ${p//,/ }; do valid_port "$x" || { red "端口无效: $x"; exit 1; }; LISTEN="${LISTEN:+$LISTEN,}:$x"; done
    fi
    read -rp "合法路径 [$VPATH]: " v; [ -n "$v" ] && VPATH="$v"
    read -rp "白名单IP(逗号分隔，可留空) [$ALLOW]: " a; [ -n "$a" ] && ALLOW="$a"

    if [ ! -f "$REDIS_ENV" ]; then
        yellow "未找到 $REDIS_ENV，现在配置 Redis（与 HAProxy 节点共用同一个库）"
        read -rp "REDIS_HOST [127.0.0.1]: " rh
        read -rp "REDIS_PORT [6379]: " rp
        read -rsp "REDIS_PASS: " rpw; echo
        read -rp "NODE_ID [$(hostname)]: " nid
        mkdir -p "$(dirname "$REDIS_ENV")"
        cat > "$REDIS_ENV" <<EOF
REDIS_HOST="${rh:-127.0.0.1}"
REDIS_PORT=${rp:-6379}
REDIS_PASS="$rpw"
NODE_ID="${nid:-$(hostname)}"
EOF
        chmod 600 "$REDIS_ENV"
    fi

    download_bin
    save_conf
    write_unit
    systemctl enable --now "$SERVICE"
    sleep 1
    do_status
}

do_ports() { load_conf; echo "当前监听: ${LISTEN//:/}"; echo "转发到:   $TARGET"; }

do_addport() {
    load_conf
    local p="$1"; [ -z "$p" ] && read -rp "要添加的端口: " p
    valid_port "$p" || { red "端口无效"; return 1; }
    [[ ",$LISTEN," == *",:$p,"* ]] && { yellow "端口 $p 已存在"; return 0; }
    LISTEN="${LISTEN:+$LISTEN,}:$p"
    save_conf; systemctl restart "$SERVICE"
    green "已添加端口 $p，当前: ${LISTEN//:/}"
    yellow "如有防火墙/安全组，记得放行 $p"
}

do_delport() {
    load_conf
    local p="$1"; [ -z "$p" ] && read -rp "要删除的端口: " p
    local new=""
    for x in ${LISTEN//,/ }; do [ "$x" != ":$p" ] && new="${new:+$new,}$x"; done
    [ -z "$new" ] && { red "至少保留一个端口"; return 1; }
    LISTEN="$new"; save_conf; systemctl restart "$SERVICE"
    green "已删除端口 $p，当前: ${LISTEN//:/}"
}

do_target() {
    load_conf
    local t="$1"; [ -z "$t" ] && read -rp "新的 B 服务器地址 ip:port: " t
    [ -z "$t" ] && return 1
    TARGET="$t"; save_conf; systemctl restart "$SERVICE"; green "已改为转发到 $TARGET"
}

do_status()  { systemctl --no-pager status "$SERVICE" | head -15; }
do_restart() { systemctl restart "$SERVICE" && green "已重启"; do_status; }
do_stop()    { systemctl stop "$SERVICE" && green "已停止"; }
do_log()     { journalctl -u "$SERVICE" -n 100 -f --no-pager; }
do_banlog()  { journalctl -u "$SERVICE" --no-pager | grep "拉黑" | tail -50; }
do_update()  { download_bin; systemctl restart "$SERVICE"; do_status; }

do_uninstall() {
    read -rp "确认卸载 gotcp-filter？(y/N): " y; [ "$y" != "y" ] && return
    systemctl disable --now "$SERVICE" 2>/dev/null
    rm -f "$UNIT" "$BIN"; systemctl daemon-reload
    green "已卸载（保留配置 $CONF 和 $REDIS_ENV）"
}

menu() {
    while true; do
        echo
        green "======== gotcp-filter 管理 ========"
        do_ports 2>/dev/null
        echo " 1. 安装 / 重新配置      2. 添加端口"
        echo " 3. 删除端口             4. 修改 B 服务器"
        echo " 5. 查看实时日志         6. 查看拉黑记录"
        echo " 7. 重启                 8. 停止"
        echo " 9. 状态                10. 更新程序"
        echo "11. 卸载                 0. 退出"
        read -rp "选择: " n
        case "$n" in
            1) do_install ;; 2) do_addport ;; 3) do_delport ;; 4) do_target ;;
            5) do_log ;; 6) do_banlog ;; 7) do_restart ;; 8) do_stop ;;
            9) do_status ;; 10) do_update ;; 11) do_uninstall ;; 0) exit 0 ;;
        esac
    done
}

case "$1" in
    install) do_install ;; addport) do_addport "$2" ;; delport) do_delport "$2" ;;
    ports) do_ports ;; target) do_target "$2" ;; log) do_log ;; banlog) do_banlog ;;
    restart) do_restart ;; stop) do_stop ;; status) do_status ;;
    update) do_update ;; uninstall) do_uninstall ;; *) menu ;;
esac
