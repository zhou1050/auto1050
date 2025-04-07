#!/bin/bash

echo "✅ 开启 IP 转发..."
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf

echo "✅ 设置 BBR 拥塞控制和网络优化参数..."
cat >> /etc/sysctl.conf <<EOF

# VPN 加速优化配置
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# 网络缓冲区优化
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 32768
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10240 65535
EOF

sysctl -p

echo "✅ 设置 NAT 转发规则..."
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -s 192.168.18.0/24 -j ACCEPT

echo "✅ 安装 iptables-persistent 并保存防火墙规则..."
apt-get install -y iptables-persistent
netfilter-persistent save

echo "✅ 优化 PPP 配置（MTU + DNS）..."
sed -i '/^mtu /d' /etc/ppp/options.xl2tpd
sed -i '/^mru /d' /etc/ppp/options.xl2tpd
sed -i '/^ms-dns /d' /etc/ppp/options.xl2tpd

cat >> /etc/ppp/options.xl2tpd <<EOF
mtu 1410
mru 1410
ms-dns 8.8.8.8
ms-dns 1.1.1.1
EOF

echo "✅ 重启 VPN 服务..."
systemctl restart ipsec
systemctl restart xl2tpd

echo -e "\n🎉 全部完成！你的 L2TP VPN 已成功优化！速度更快，连接更稳！"
