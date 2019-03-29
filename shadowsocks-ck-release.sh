#!/usr/bin/env bash

# Forked and modified by cbeuw from https://github.com/teddysun/shadowsocks_install/blob/master/shadowsocks-all.sh

PATH=$PATH:/usr/local/bin
export PATH

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}] This script must be run as root!" && exit 1

shadowsocks_libev_config="/etc/shadowsocks-libev/config.json"

# Stream Ciphers
common_ciphers=(
aes-256-gcm
aes-192-gcm
aes-128-gcm
aes-256-ctr
aes-192-ctr
aes-128-ctr
aes-256-cfb
aes-192-cfb
aes-128-cfb
camellia-128-cfb
camellia-192-cfb
camellia-256-cfb
xchacha20-ietf-poly1305
chacha20-ietf-poly1305
chacha20-ietf
chacha20
salsa20
rc4-md5
)

archs=(
amd64
386
arm
arm64
)

check_sys(){
	local checkType=$1
	local value=$2

	local release=''
	local systemPackage=''

	if [[ -f /etc/redhat-release ]]; then
		release="centos"
		systemPackage="yum"
	elif grep -Eqi "debian" /etc/issue; then
		release="debian"
		systemPackage="apt"
	elif grep -Eqi "ubuntu" /etc/issue; then
		release="ubuntu"
		systemPackage="apt"
	elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
		release="centos"
		systemPackage="yum"
	elif grep -Eqi "debian|raspbian" /proc/version; then
		release="debian"
		systemPackage="apt"
	elif grep -Eqi "ubuntu" /proc/version; then
		release="ubuntu"
		systemPackage="apt"
	elif grep -Eqi "centos|red hat|redhat" /proc/version; then
		release="centos"
		systemPackage="yum"
	fi

	if [[ "${checkType}" == "sysRelease" ]]; then
		if [ "${value}" == "${release}" ]; then
			return 0
		else
			return 1
		fi
	elif [[ "${checkType}" == "packageManager" ]]; then
		if [ "${value}" == "${systemPackage}" ]; then
			return 0
		else
			return 1
		fi
	fi
}

install_cloak(){
	while true
	do
		echo -e "Please choose your system's architecture:"

		for ((i=1;i<=${#archs[@]};i++ )); do
			hint="${archs[$i-1]}"
			echo -e "${green}${i}${plain}) ${hint}"
		done
		read -p "What's your architecture? (Default: ${archs[0]}):" pick
		[ -z "$pick" ] && pick=1
		expr ${pick} + 1 &>/dev/null
		if [ $? -ne 0 ]; then
			echo -e "[${red}Error${plain}] Please enter a number"
			continue
		fi
		if [[ "$pick" -lt 1 || "$pick" -gt ${#archs[@]} ]]; then
			echo -e "[${red}Error${plain}] Please enter a number between 1 and ${#archs[@]}"
			continue
		fi
		ckarch=${archs[$pick-1]}
		echo
		echo "arch = ${ckarch}"
		echo
		break
	done

	url=$(wget -O - -o /dev/null https://api.github.com/repos/cbeuw/Cloak/releases/latest | grep "/ck-server-linux-$ckarch-" | grep -P 'https(.*)[^"]' -o)
	wget -O ck-server $url
	chmod +x ck-server
	sudo mv ck-server /usr/local/bin
}


install_shadowsocks_libev(){
	if check_sys packageManager yum; then
		dnf copr enable librehat/shadowsocks
		yum update
		yum -y install shadowsocks
	elif check_sys packageManager apt; then
		apt -y update
		apt install shadowsocks-libev
	fi

}

generate_credentials(){
	if [ "${cloak}" == "y" ] || [ "${cloak}" == "Y" ]; then
		ckauid=$(ck-server -u)
		IFS=, read ckpub ckpv <<< $(ck-server -k)
	fi
}


install_prepare_cloak(){
	while true
	do
		echo -e "Do you want install Cloak for shadowsocks-libev? [y/n]"
		read -p "(default: y):" cloak 
		[ -z "$cloak" ] && cloak=y
		case "${cloak}" in
			y|Y|n|N)
				echo
				echo "You choose = ${cloak}"
				echo
				break
				;;
			*)
				echo -e "[${red}Error${plain}] Please only enter [y/n]"
				;;
		esac
	done

	if [ "${cloak}" == "y" ] || [ "${cloak}" == "Y" ]; then
		echo -e "Please enter a redirection IP for Cloak (leave blank to set it to 204.79.197.200:443 of bing.com):"
		read -p "" ckwebaddr
		[ -z "$ckwebaddr" ] && ckwebaddr="204.79.197.200:443"

		echo -e "Where do you want to put the userinfo.db? (default $HOME)"
		read -p "" ckdbp
		[ -z "$ckdbp" ] && ckdbp=$HOME
	fi
}

get_ip(){
	[ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipv4.icanhazip.com )
	[ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipinfo.io/ip )
	[ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ip.42.pl/ip )
	echo ${IP}
}

get_ipv6(){
		local ipv6=$(wget -qO- -t1 -T2 ipv6.icanhazip.com)
			[ -z ${ipv6} ] && return 1 || return 0
		}



config_shadowsocks(){
	local server_value="\"0.0.0.0\""
	if get_ipv6; then
		server_value="[\"[::0]\",\"0.0.0.0\"]"
	fi

	if [ ! -d "$(dirname ${shadowsocks_libev_config})" ]; then
		mkdir -p $(dirname ${shadowsocks_libev_config})
	fi

	if [ "${cloak}" == "y" ] || [ "${cloak}" == "Y" ]; then
		cat > ${shadowsocks_libev_config}<<-EOF
{
    "server":${server_value},
    "server_port":${shadowsocksport},
    "password":"${shadowsockspwd}",
    "timeout":300,
    "user":"nobody",
    "method":"${shadowsockscipher}",
    "fast_open":false,
    "nameserver":"8.8.8.8",
    "plugin":"ck-server",
    "plugin_opts":"WebServerAddr=${ckwebaddr};PrivateKey=${ckpv};AdminUID=${ckauid};DatabasePath=${ckdbp}/userinfo.db;BackupDirPath=${ckdbp}"
}
EOF

     else
	     cat > ${shadowsocks_libev_config}<<-EOF
{
    "server":${server_value},
    "server_port":${shadowsocksport},
    "password":"${shadowsockspwd}",
    "timeout":300,
    "user":"nobody",
    "method":"${shadowsockscipher}",
    "fast_open":false,
    "nameserver":"8.8.8.8",
    "mode":"tcp_and_udp"
}
EOF

fi
}


install(){
	echo "Please enter password for shadowsocks-libev:"
	read -p "(Default password: github.com):" shadowsockspwd
	[ -z "${shadowsockspwd}" ] && shadowsockspwd="github.com"
	echo
	echo "password = ${shadowsockspwd}"
	echo

	while true
	do
		dport=443
		echo -e "Please enter a port for shadowsocks-libev [1-65535]"
		read -p "(Default port: ${dport}):" shadowsocksport
		[ -z "${shadowsocksport}" ] && shadowsocksport=${dport}
		expr ${shadowsocksport} + 1 &>/dev/null
		if [ $? -eq 0 ]; then
			if [ ${shadowsocksport} -ge 1 ] && [ ${shadowsocksport} -le 65535 ] && [ ${shadowsocksport:0:1} != 0 ]; then
				echo
				echo "port = ${shadowsocksport}"
				echo
				break
			fi
		fi
		echo -e "[${red}Error${plain}] Please enter a correct number [1-65535]"
	done

	while true
	do
		echo -e "Please select stream cipher for shadowsocks-libev:"

		for ((i=1;i<=${#common_ciphers[@]};i++ )); do
			hint="${common_ciphers[$i-1]}"
			echo -e "${green}${i}${plain}) ${hint}"
		done
		read -p "Which cipher you'd select(Default: ${common_ciphers[0]}):" pick
		[ -z "$pick" ] && pick=1
		expr ${pick} + 1 &>/dev/null
		if [ $? -ne 0 ]; then
			echo -e "[${red}Error${plain}] Please enter a number"
			continue
		fi
		if [[ "$pick" -lt 1 || "$pick" -gt ${#common_ciphers[@]} ]]; then
			echo -e "[${red}Error${plain}] Please enter a number between 1 and ${#common_ciphers[@]}"
			continue
		fi
		shadowsockscipher=${common_ciphers[$pick-1]}
		echo
		echo "cipher = ${shadowsockscipher}"
		echo
		break
	done
	install_shadowsocks_libev
	install_prepare_cloak
	install_cloak
	generate_credentials
	config_shadowsocks
	install_completed_libev
	echo "Enjoy!"
}

install_completed_libev(){
	#clear
	echo
	echo -e "Congratulations, ${green}shadowsocks-libev${plain} server install completed!"
	echo -e "Your Server IP        : ${red} $(get_ip) ${plain}"
	echo -e "Your Server Port      : ${red} ${shadowsocksport} ${plain}"
	echo -e "Your Password         : ${red} ${shadowsockspwd} ${plain}"
	echo -e "Your Encryption Method: ${red} ${shadowsockscipher} ${plain}"
	echo -e "Your Cloak's Public Key: ${red} ${ckpub} ${plain}"
	echo -e "Your Cloak's Private Key: ${red} ${ckpv} ${plain}"
	echo -e "Your Cloak's AdminUID: ${red} ${ckauid} ${plain}"
}


uninstall(){
	printf "Are you sure uninstall ${red}shadowsocks-libev${plain}? [y/n]\n"
	read -p "(default: n):" answer
	[ -z ${answer} ] && answer="n"
	if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
		if check_sys packageManager yum; then
			yum -ye shadowsocks
		elif check_sys packageManager apt; then
			apt remove -y --purge shadowsocks-libev
		fi
		rm -rf /usr/local/bin/ck-server
	else
		echo
		echo -e "[${green}Info${plain}] shadowsocks-libev uninstall cancelled, nothing to do..."
		echo
	fi
}

# Initialization step
action=$1
[ -z $1 ] && action=install
case "${action}" in
	install|uninstall)
		${action}
		;;
	*)
		echo "Arguments error! [${action}]"
		echo "Usage: $(basename $0) [install|uninstall]"
		;;
esac
