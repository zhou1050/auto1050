#!/bin/bash

set -e

GOST_VERSION="2.12.0"
GOST_PATH="/usr/local/bin/gost"
START_PORT=10800
END_PORT=10823
USER="111"
PASS="111"

# 1. 自动识别架构
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)   ARCH_TAG="amd64" ;;
  i386|i686) ARCH_TAG="386" ;;
  aarch64) ARCH_TAG="arm64" ;;
  arm*)    ARCH_TAG="armv7" ;;
  *)       echo "❌ 不支持的架构：$ARCH"; exit 1 ;;
esac

# 2. 下载并安装 gost
if [ ! -f "$GOST_PATH" ]; then
  echo "📦 正在下载 GOST ($ARCH_TAG)..."
  TEMP_DIR=$(mktemp -d)
  cd $TEMP_DIR
  wget -q "https://github.com/ginuerzh/gost/releases/download/v$GOST_VERSION/gost_${GOST_VERSION}_linux_${ARCH_TAG}.tar.gz"
  tar -xzf "gost_${GOST_VERSION}_linux_${ARCH_TAG}.tar.gz"
  chmod +x gost
  mv gost "$GOST_PATH"
  cd -
  rm -rf "$TEMP_DIR"
  echo "✅ GOST 安装成功：$GOST_PATH"
fi

# 3. 写入 systemd 模板服务
SERVICE_FILE="/etc/systemd/system/gost-socks5@.service"
cat <<EOF > $SERVICE_FILE
[Unit]
Description=GOST SOCKS5 Proxy on port %i
After=network.target

[Service]
ExecStart=$GOST_PATH -L socks5://$USER:$PASS@:%i
Restart=always
RestartSec=2
User=root
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# 4. 重新加载 systemd
systemctl daemon-reexec
systemctl daemon-reload

# 5. 启动所有端口服务
for port in $(seq $START_PORT $END_PORT); do
    systemctl enable --now gost-socks5@$port
done

echo "✅ 已启用 GOST 守护服务（$START_PORT 到 $END_PORT）"

# 6. 系统连接数扩容建议
LIMITS_CONF="/etc/security/limits.conf"
SYSCTL_CONF="/etc/sysctl.conf"

if ! grep -q "nofile" "$LIMITS_CONF"; then
    echo "* soft nofile 65535" >> "$LIMITS_CONF"
    echo "* hard nofile 65535" >> "$LIMITS_CONF"
    echo "✅ 已写入 limits.conf"
fi

cat <<EOF | tee -a $SYSCTL_CONF >/dev/null
fs.file-max = 2097152
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_tw_reuse = 1
EOF

sysctl -p

echo "🎉 GOST 多端口 SOCKS5 服务部署完成！"
