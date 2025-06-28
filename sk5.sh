#!/bin/bash

GOST_PATH="/usr/local/bin/gost"
START_PORT=10800
END_PORT=10823
USER="111"
PASS="111"

# 检查gost是否存在
if [ ! -f "$GOST_PATH" ]; then
    echo "❌ gost 未安装，请将 gost 放在 $GOST_PATH"
    exit 1
fi

# 写入 systemd 模板服务文件
SERVICE_FILE="/etc/systemd/system/gost-socks5@.service"
echo "[Unit]" > $SERVICE_FILE
echo "Description=GOST SOCKS5 Proxy on port %i" >> $SERVICE_FILE
echo "After=network.target" >> $SERVICE_FILE
echo "" >> $SERVICE_FILE
echo "[Service]" >> $SERVICE_FILE
echo "ExecStart=$GOST_PATH -L socks5://$USER:$PASS@:%i" >> $SERVICE_FILE
echo "Restart=always" >> $SERVICE_FILE
echo "RestartSec=2" >> $SERVICE_FILE
echo "User=nobody" >> $SERVICE_FILE
echo "LimitNOFILE=1048576" >> $SERVICE_FILE
echo "NoNewPrivileges=true" >> $SERVICE_FILE
echo "" >> $SERVICE_FILE
echo "[Install]" >> $SERVICE_FILE
echo "WantedBy=multi-user.target" >> $SERVICE_FILE

# 重新加载 systemd
systemctl daemon-reexec
systemctl daemon-reload

# 启动每个端口
for port in $(seq $START_PORT $END_PORT); do
    systemctl enable --now gost-socks5@${port}
done

echo "✅ 已启用 GOST 守护服务（$START_PORT 到 $END_PORT）"


systemctl status gost-socks5@10800
for p in $(seq 10800 10823); do systemctl disable --now gost-socks5@$p; done
journalctl -u gost-socks5@10800 -f


连接数扩容
echo "* soft nofile 65535" >> /etc/security/limits.conf
echo "* hard nofile 65535" >> /etc/security/limits.conf
编辑 /etc/sysctl.conf 加入：

fs.file-max = 2097152
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_tw_reuse = 1
sysctl -p


自动脚本
#!/bin/bash

GOST_PATH="/usr/local/bin/gost"
START_PORT=10800
END_PORT=10823
USER="111"
PASS="111"

# 检查gost是否存在
if [ ! -f "$GOST_PATH" ]; then
    echo "❌ gost 未安装，请将 gost 放在 $GOST_PATH"
    exit 1
fi

# 写入 systemd 模板服务文件
SERVICE_FILE="/etc/systemd/system/gost-socks5@.service"
echo "[Unit]" > $SERVICE_FILE
echo "Description=GOST SOCKS5 Proxy on port %i" >> $SERVICE_FILE
echo "After=network.target" >> $SERVICE_FILE
echo "" >> $SERVICE_FILE
echo "[Service]" >> $SERVICE_FILE
echo "ExecStart=$GOST_PATH -L socks5://$USER:$PASS@:%i" >> $SERVICE_FILE
echo "Restart=always" >> $SERVICE_FILE
echo "RestartSec=2" >> $SERVICE_FILE
echo "User=nobody" >> $SERVICE_FILE
echo "LimitNOFILE=1048576" >> $SERVICE_FILE
echo "NoNewPrivileges=true" >> $SERVICE_FILE
echo "" >> $SERVICE_FILE
echo "[Install]" >> $SERVICE_FILE
echo "WantedBy=multi-user.target" >> $SERVICE_FILE

# 重新加载 systemd
systemctl daemon-reexec
systemctl daemon-reload

# 启动每个端口
for port in $(seq $START_PORT $END_PORT); do
    systemctl enable --now gost-socks5@${port}
done

echo "✅ 已启用 GOST 守护服务（$START_PORT 到 $END_PORT）"


systemctl status gost-socks5@10800
for p in $(seq 10800 10823); do systemctl disable --now gost-socks5@$p; done
journalctl -u gost-socks5@10800 -f


连接数扩容
echo "* soft nofile 65535" >> /etc/security/limits.conf
echo "* hard nofile 65535" >> /etc/security/limits.conf
编辑 /etc/sysctl.conf 加入：

fs.file-max = 2097152
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_tw_reuse = 1
sysctl -p
