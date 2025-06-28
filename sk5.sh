#!/bin/bash

GOST_PATH="/usr/local/bin/gost"
START_PORT=10800
END_PORT=10823
USER="111"
PASS="111"
SERVICE_FILE="/etc/systemd/system/gost-socks5@.service"

# 检查 gost 是否存在
if [ ! -f "$GOST_PATH" ]; then
    echo "❌ gost 未安装，请将 gost 放在 $GOST_PATH"
    exit 1
fi

# 写入 systemd 模板服务文件（不使用 User=nobody）
cat > $SERVICE_FILE <<EOF
[Unit]
Description=GOST SOCKS5 Proxy on port %i
After=network.target

[Service]
ExecStart=$GOST_PATH -L socks5://$USER:$PASS@:%i
Restart=always
RestartSec=2
#User=nobody
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd 配置
systemctl daemon-reexec
systemctl daemon-reload

# 启动每个端口
for port in $(seq $START_PORT $END_PORT); do
    systemctl enable --now gost-socks5@${port}
done

echo "✅ 已启用 GOST 守护服务（$START_PORT 到 $END_PORT）"

# 修改连接数限制
LIMITS_FILE="/etc/security/limits.conf"
if ! grep -q "soft nofile 65535" $LIMITS_FILE; then
    echo "* soft nofile 65535" >> $LIMITS_FILE
    echo "* hard nofile 65535" >> $LIMITS_FILE
    echo "✅ 已写入 /etc/security/limits.conf"
fi

# 修改内核参数
SYSCTL_FILE="/etc/sysctl.conf"
SYSCTL_SETTINGS=(
"fs.file-max = 2097152"
"net.core.somaxconn = 65535"
"net.ipv4.tcp_max_syn_backlog = 65535"
"net.ipv4.ip_local_port_range = 1024 65000"
"net.ipv4.tcp_tw_reuse = 1"
)

for setting in "${SYSCTL_SETTINGS[@]}"; do
    key=$(echo "$setting" | cut -d= -f1 | xargs)
    if ! grep -q "^$key" $SYSCTL_FILE; then
        echo "$setting" >> $SYSCTL_FILE
    fi
done

sysctl -p
echo "✅ 已应用 sysctl 内核参数优化"

# 可选：查看 10800 服务状态（调试）
systemctl status gost-socks5@10800 --no-pager
