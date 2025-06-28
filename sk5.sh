#!/bin/bash

GOST_PATH="/usr/local/bin/gost"
SERVICE_FILE="/etc/systemd/system/gost-socks5@.service"
LIMITS_CONF="/etc/security/limits.conf"
SYSCTL_CONF="/etc/sysctl.conf"
LOG_DIR="/var/log/gost_manager"

if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本"
    exit 1
fi

mkdir -p "$LOG_DIR"

install_gost() {
    echo "==> 安装官方 GOST 二进制..."

    GOST_VERSION="2.12.0"
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64) ARCH_TAG="amd64" ;;
        i386|i686) ARCH_TAG="386" ;;
        aarch64) ARCH_TAG="arm64" ;;
        arm*) ARCH_TAG="armv7" ;;
        *)
            echo "❌ 不支持的架构: $ARCH"
            return 1
            ;;
    esac

    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"

    #URL="https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}/gost_${GOST_VERSION}_linux_${ARCH_TAG}.tar.gz"
    URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost_${GOST_VERSION}_linux_${ARCH_TAG}.tar.gz"
    echo "📦 下载地址: $URL"

    wget -q "$URL" -O gost.tar.gz || { echo "❌ 下载失败"; return 1; }
    tar -xzf gost.tar.gz || { echo "❌ 解压失败"; return 1; }

    if [ ! -f gost ]; then
        echo "❌ 没有找到可执行文件 gost"
        return 1
    fi

    chmod +x gost
    mv gost "$GOST_PATH"
    cd -
    rm -rf "$TMP_DIR"

    echo "✅ GOST 已安装到 $GOST_PATH"
}

validate_ports() {
    if ! [[ "$START_PORT" =~ ^[0-9]+$ ]] || ! [[ "$END_PORT" =~ ^[0-9]+$ ]]; then
        echo "❌ 端口必须为数字"
        return 1
    fi
    if [ "$START_PORT" -gt "$END_PORT" ]; then
        echo "❌ 起始端口不能大于结束端口"
        return 1
    fi
    if [ "$START_PORT" -lt 1024 ] || [ "$END_PORT" -gt 65535 ]; then
        echo "❌ 端口范围建议在 1024-65535 之间"
        return 1
    fi
    return 0
}

set_params() {
    read -rp "请输入用户名: " USER
    if [ -z "$USER" ]; then
        echo "❌ 用户名不能为空"
        return 1
    fi
    read -rp "请输入密码: " PASS
    if [ -z "$PASS" ]; then
        echo "❌ 密码不能为空"
        return 1
    fi
    read -rp "请输入起始端口（1024-65535）: " START_PORT
    read -rp "请输入结束端口（1024-65535）: " END_PORT
    validate_ports || return 1
    write_service_template
}

write_service_template() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=GOST SOCKS5 Proxy on port %i
After=network.target

[Service]
ExecStart=$GOST_PATH -L socks5://$USER:$PASS@:%i
Restart=always
RestartSec=2
LimitNOFILE=1048576
NoNewPrivileges=true
StandardOutput=file:$LOG_DIR/gost-%i.log
StandardError=file:$LOG_DIR/gost-%i.err

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reexec
    systemctl daemon-reload
    echo "✅ systemd 服务模板已写入"
}

check_port_usage() {
    local port=$1
    if ss -ltn | grep -q ":$port "; then
        echo "❌ 端口 $port 已被占用"
        return 1
    fi
    return 0
}

start_services() {
    if ! validate_ports; then
        echo "请先通过选项 2 设置正确的端口范围"
        return
    fi

    echo "即将启动端口范围：$START_PORT 到 $END_PORT"
    read -rp "确认启动这些端口的服务吗？(y/n): " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "已取消启动"; return; }

    local fail_count=0
    for port in $(seq $START_PORT $END_PORT); do
        if check_port_usage "$port"; then
            systemctl enable --now gost-socks5@"$port"
            echo "✅ 启动端口 $port"
        else
            echo "跳过端口 $port"
            ((fail_count++))
        fi
    done
    echo "启动完成，$fail_count 个端口因被占用未启动"
}

stop_all_services() {
    if ! validate_ports; then
        echo "请先通过选项 2 设置正确的端口范围"
        return
    fi
    for port in $(seq $START_PORT $END_PORT); do
        systemctl disable --now gost-socks5@"$port"
    done
    echo "🛑 已停止所有实例"
}

stop_one_service() {
    read -rp "请输入端口号: " port
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "❌ 端口格式错误"
        return
    fi
    systemctl disable --now gost-socks5@"$port"
    echo "🛑 端口 $port 服务已停止"
}

expand_limits() {
    echo "==> 扩容连接数..."
    if ! grep -q "nofile" "$LIMITS_CONF"; then
        echo -e "* soft nofile 65535\n* hard nofile 65535" >> "$LIMITS_CONF"
        echo "已写入 limits.conf"
    else
        echo "limits.conf 已包含 nofile 设置，跳过写入"
    fi

    if ! grep -q "fs.file-max" "$SYSCTL_CONF"; then
        cat >> "$SYSCTL_CONF" <<EOF

fs.file-max = 2097152
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_tw_reuse = 1
EOF
        echo "已写入 sysctl.conf"
    else
        echo "sysctl.conf 已包含相关内核参数，跳过写入"
    fi

    sysctl -p
    echo "✅ 系统连接数扩容完成"
}

view_connections() {
    echo "监听端口的连接数（本地端口）:"
    ss -ant state established "( sport >= :$START_PORT and sport <= :$END_PORT )" | awk '{print $4}' | cut -d: -f2 | sort | uniq -c
}

view_status() {
    if ! validate_ports; then
        echo "请先通过选项 2 设置正确的端口范围"
        return
    fi
    for port in $(seq $START_PORT $END_PORT); do
        if systemctl is-active gost-socks5@"$port" >/dev/null; then
            echo "✅ 端口 $port 运行中"
        else
            echo "❌ 端口 $port 未运行"
        fi
    done
}

view_process_count() {
    echo "当前 GOST 进程数量: $(pgrep -fc gost)"
}

view_network_sessions() {
    echo "TCP 会话："
    ss -antp | grep gost | awk '{print $5}' | cut -d: -f2 | sort | uniq -c
    echo ""
    echo "UDP 会话："
    ss -anup | grep gost | awk '{print $5}' | cut -d: -f2 | sort | uniq -c
}

while true; do
    echo -e "\n========= GOST 管理脚本 ========="
    echo "1. 下载并安装 GOST"
    echo "2. 设置用户名/密码和端口范围"
    echo "3. 启动 GOST 实例"
    echo "4. 扩容连接数"
    echo "5. 查看当前运行状态"
    echo "6. 查看端口连接数"
    echo "7. 停止所有实例"
    echo "8. 停止指定实例"
    echo "9. 查看 GOST 进程数量"
    echo "10. 查看每个端口 TCP/UDP 会话数"
    echo "0. 退出脚本"
    echo "=================================="
    read -rp "请输入选项: " opt
    case $opt in
        1) install_gost ;;
        2) set_params ;;
        3) start_services ;;
        4) expand_limits ;;
        5) view_status ;;
        6) view_connections ;;
        7) stop_all_services ;;
        8) stop_one_service ;;
        9) view_process_count ;;
        10) view_network_sessions ;;
        0) exit 0 ;;
        *) echo "❌ 无效选项" ;;
    esac
done
