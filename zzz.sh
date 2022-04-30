#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

cur_dir=`pwd`

libreswan_filename="libreswan-3.27"
download_root_url="https://dl.lamp.sh/files"

rootness(){
    if [[ $EUID -ne 0 ]]; then
       echo "Error:This script must be run as root!" 1>&2
       exit 1
    fi
}

tunavailable(){
    if [[ ! -e /dev/net/tun ]]; then
        echo "Error:TUN/TAP is not available!" 1>&2
        exit 1
    fi
}

disable_selinux(){
if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
fi
}

get_opsy(){
    [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

get_os_info(){
    IP=$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1 )
    [ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipv4.icanhazip.com )

    local cname=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
    local freq=$( awk -F: '/cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local tram=$( free -m | awk '/Mem/ {print $2}' )
    local swap=$( free -m | awk '/Swap/ {print $2}' )
    local up=$( awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60;d=$1%60} {printf("%ddays, %d:%d:%d\n",a,b,c,d)}' /proc/uptime )
    local load=$( w | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local opsy=$( get_opsy )
    local arch=$( uname -m )
    local lbit=$( getconf LONG_BIT )
    local host=$( hostname )
    local kern=$( uname -r )

    echo "########## System Information ##########"
    echo 
    echo "CPU model            : ${cname}"
    echo "Number of cores      : ${cores}"
    echo "CPU frequency        : ${freq} MHz"
    echo "Total amount of ram  : ${tram} MB"
    echo "Total amount of swap : ${swap} MB"
    echo "System uptime        : ${up}"
    echo "Load average         : ${load}"
    echo "OS                   : ${opsy}"
    echo "Arch                 : ${arch} (${lbit} Bit)"
    echo "Kernel               : ${kern}"
    echo "Hostname             : ${host}"
    echo "IPv4 address         : ${IP}"
    echo 
    echo "########################################"
}



is_64bit(){
    if [ `getconf WORD_BIT` = '32' ] && [ `getconf LONG_BIT` = '64' ] ; then
        return 0
    else
        return 1
    fi
}

download_file(){
    if [ -s ${1} ]; then
        echo "$1 [found]"
    else
        echo "$1 not found!!!download now..."
        if ! wget -c -t3 -T60 ${download_root_url}/${1}; then
            echo "Failed to download $1, please download it to ${cur_dir} directory manually and try again."
            exit 1
        fi
    fi
}



preinstall_l2tp(){

    echo
    if [ -d "/proc/vz" ]; then
        echo -e "\033[41;37m WARNING: \033[0m Your VPS is based on OpenVZ, and IPSec might not be supported by the kernel."
        echo "Continue installation? (y/n)"
        read -p "(Default: n)" agree
        [ -z ${agree} ] && agree="n"
        if [ "${agree}" == "n" ]; then
            echo
            echo "L2TP installation cancelled."
            echo
            exit 0
        fi
    fi
    echo
    echo "Please enter IP-Range:"
    read -p "(Default Range: 192.168.18):" iprange
    [ -z ${iprange} ] && iprange="192.168.18"

    echo "Please enter PSK:"
    read -p "(Default PSK: 88888888):" mypsk
    [ -z ${mypsk} ] && mypsk="88888888"

    echo "Please enter Username:"
    read -p "(Default Username: zzz@111):" username
    [ -z ${username} ] && username="zzz@111"

    password=`rand`
    echo "Please enter ${username}'s password:"
    read -p "(Default Password: ${password}):" tmppassword
    [ ! -z ${tmppassword} ] && password=${tmppassword}

    echo
    echo "ServerIP:${IP}"
    echo "Server Local IP:${iprange}.1"
    echo "Client Remote IP Range:${iprange}.2-${iprange}.254"
    echo "PSK:${mypsk}"
    echo
    echo "Press any key to start... or press Ctrl + C to cancel."
    char=`get_char`

}

install_l2tp(){

    mknod /dev/random c 1 9


        echo "Adding the EPEL repository..."
        yum -y install epel-release yum-utils
        [ ! -f /etc/yum.repos.d/epel.repo ] && echo "Install EPEL repository failed, please check it." && exit 1
        yum-config-manager --enable epel
        echo "Adding the EPEL repository complete..."

            yum -y install ppp libreswan xl2tpd iptables-services
            yum_install


}

config_install(){

    cat > /etc/ipsec.conf<<EOF
version 2.0

config setup
    protostack=netkey
    nhelpers=0
    uniqueids=no
    interfaces=%defaultroute
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:!${iprange}.0/24

conn l2tp-psk
    rightsubnet=vhost:%priv
    also=l2tp-psk-nonat

conn l2tp-psk-nonat
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=%defaultroute
    leftid=${IP}
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    dpddelay=40
    dpdtimeout=130
    dpdaction=clear
    sha2-truncbug=yes
EOF

    cat > /etc/ipsec.secrets<<EOF
%any %any : PSK "${mypsk}"
EOF

    cat > /etc/xl2tpd/xl2tpd.conf<<EOF
[global]
port = 1701

[lns default]
ip range = ${iprange}.2-${iprange}.254
local ip = ${iprange}.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

    cat > /etc/ppp/options.xl2tpd<<EOF
ipcp-accept-local
ipcp-accept-remote
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
hide-password
idle 1800
mtu 1400
mru 1400
nodefaultroute
debug
proxyarp
connect-delay 5000
EOF

    rm -f /etc/ppp/chap-secrets
    cat > /etc/ppp/chap-secrets<<EOF
# Secrets for authentication using CHAP
# client    server    secret    IP addresses
${username}    l2tpd    ${password}      ${iprange}.2
EOF

}


yum_install(){

    config_install

    cp -pf /etc/sysctl.conf /etc/sysctl.conf.bak

    echo "# Added by L2TP VPN" >> /etc/sysctl.conf
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_syncookies=1" >> /etc/sysctl.conf
    echo "net.ipv4.icmp_echo_ignore_broadcasts=1" >> /etc/sysctl.conf
    echo "net.ipv4.icmp_ignore_bogus_error_responses=1" >> /etc/sysctl.conf

    for each in `ls /proc/sys/net/ipv4/conf/`; do
        echo "net.ipv4.conf.${each}.accept_source_route=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.accept_redirects=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.send_redirects=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.rp_filter=0" >> /etc/sysctl.conf
    done
    sysctl -p



    systemctl enable ipsec
    systemctl enable xl2tpd


    systemctl restart ipsec
    systemctl restart xl2tpd
    echo "Checking ipsec status..."
    systemctl -a | grep ipsec
    echo "Checking xl2tpd status..."
    systemctl -a | grep xl2tpd


}

finally(){

    cd ${cur_dir}
    rm -fr ${cur_dir}/l2tp
    # create l2tp command
    cp -f ${cur_dir}/`basename $0` /usr/bin/l2tp

    echo "Please wait a moment..."
    sleep 5
    ipsec verify
systemctl stop firewalld
systemctl disable firewalld
systemctl enable iptables
systemctl start iptables
# systemctl enable pptpd
# systemctl start pptpd

cat > /etc/sysconfig/iptables <<EOF
# Added by L2TP VPN script
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m multiport --dports 81,1723,22,44158,2021,2022,2023 -j ACCEPT
-A INPUT -p udp -m multiport --dports 500,4500,1701,1680 -j ACCEPT
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -s ${iprange}.0/24  -j ACCEPT
-A FORWARD -d ${iprange}.0/24  -j ACCEPT
-A FORWARD -i eth0 -o ppp+ -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i ppp+ -o eth0 -j ACCEPT
-A FORWARD -i ppp+ -o ppp+ -j ACCEPT

COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s ${iprange}.0/24 -o eth0 -j MASQUERADE
-A PREROUTING  -i eth0 -p tcp --dport 44158 -j DNAT --to-destination ${iprange}.2:44158
-A PREROUTING  -i eth0 -p tcp --dport 81 -j DNAT --to-destination ${iprange}.2:80
-A PREROUTING  -i eth0 -p tcp --dport 8291 -j DNAT --to-destination ${iprange}.2:8291
-A PREROUTING  -i eth0 -p udp --dport 1680 -j DNAT --to-destination ${iprange}.2:1680
COMMIT
EOF

   


    systemctl restart iptables
	# systemctl restart pptpd
    echo "Enjoy it!"
    echo

    echo "If there is no [FAILED] above, you can connect to your L2TP "
    echo "VPN Server with the default Username/Password is below:"
    echo
    echo "Server IP: ${IP}"
    echo "PSK      : ${mypsk}"
    echo "Username : ${username}"
    echo "Password : ${password}"

}


l2tp(){
    clear
    echo

    rootness
    tunavailable
    disable_selinux
    version_check
    get_os_info
    preinstall_l2tp
    install_l2tp
    finally
}



# Main process
action=$1
if [ -z ${action} ] && [ "`basename $0`" != "l2tp" ]; then
    action=install
fi

case ${action} in
    install)
        l2tp 2>&1 | tee ${cur_dir}/l2tp.log
        ;;

esac
