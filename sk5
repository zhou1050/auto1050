#!/bin/bash

# === 基础参数 ===
GOST_PATH="/usr/local/bin/gost"
SERVICE_FILE="/etc/systemd/system/gost-socks5@.service"
LIMITS_CONF="/etc/security/limits.conf"
SYSCTL_CONF="/etc/sysctl.conf"

if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本"
    exit 1
fi

install_gost() {
    echo "==> 安装 snapd 和 gost..."
    apt update && apt install -y snapd
    snap install gost
    ln -sf /snap/bin/gost "$GOST_PATH"
    echo "✅ 已安装 gost"
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
User=nobody
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reexec
    systemctl daemon-reload
}

start_services() {
    for port in $(seq $START_PORT $END_PORT); do
        systemctl enable --now gost-socks5@$port
    done
    echo "✅ 已启用 GOST 守护服务（$START_PORT 到 $END_PORT）"
}

stop_all_services() {
    for port in $(seq $START_PORT $END_PORT); do
        systemctl disable --now gost-socks5@$port
    done
    echo "🛑 所有 GOST 实例已停止"
}

stop_one_service() {
    read -p "请输入端口号: " port
    systemctl disable --now gost-socks5@$port
    echo "🛑 端口 $port 的服务已停止"
}

expand_limits() {
    echo "==> 扩容连接数..."
    grep -q 'nofile' $LIMITS_CONF || echo -e "* soft nofile 65535\n* hard nofile 65535" >> $LIMITS_CONF
    cat >> $SYSCTL_CONF <<EOF
fs.file-max = 2097152
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_tw_reuse = 1
EOF
    sysctl -p
    echo "✅ 已扩容系统连接数"
}

view_connections() {
    ss -antp | grep gost | awk '{print $5}' | cut -d: -f2 | sort | uniq -c
}

view_status() {
    for port in $(seq $START_PORT $END_PORT); do
        if systemctl is-active gost-socks5@$port >/dev/null; then
            echo "✅ 端口 $port 正在运行"
        fi
    done
}

view_process_count() {
    echo "当前 GOST 进程数量: $(pgrep -fc gost)"
}

view_network_sessions() {
    echo "TCP 会话："
    ss -antp | grep gost | awk '{print $5}' | cut -d: -f2 | sort | uniq -c
    echo "\nUDP 会话："
    ss -anup | grep gost | awk '{print $5}' | cut -d: -f2 | sort | uniq -c
}

set_params() {
    read -p "请输入用户名: " USER
    read -p "请输入密码: " PASS
    read -p "请输入起始端口（如10800）: " START_PORT
    read -p "请输入结束端口（如10823）: " END_PORT
}

while true; do
    echo -e "\n========= GOST 管理脚本 ========="
    echo "1. 安装 snapd 并安装 gost"
    echo "2. 设置用户名/密码和端口范围"
    echo "3. 启动 gost 实例"
    echo "4. 扩容连接数"
    echo "5. 查看当前运行状态"
    echo "6. 查看端口连接数"
    echo "7. 停止所有实例"
    echo "8. 停止指定实例"
    echo "9. 查看 GOST 进程数量"
    echo "10. 查看每个端口 TCP/UDP 会话数"
    echo "0. 退出脚本"
    echo "=================================="
    read -p "请输入选项: " opt
    case $opt in
        1) install_gost ;;
        2) set_params && write_service_template ;;
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
