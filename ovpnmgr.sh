#!/bin/bash
export EASYRSA=/etc/easy-rsa
export EASYRSA_VARS_FILE=$EASYRSA/vars

info() {
	printf '%s \033[32;1minfo\033[0m: %s\n' "`date -u +%Y-%m-%dT%H:%M:%SZ`" "$*"
}

error() {
	printf '%s \033[31;1merror\033[0m: %s\n' "`date -u +%Y-%m-%dT%H:%M:%SZ`" "$*"
	exit 1
}

if [[ $EUID -ne 0 ]]; then
	error 'This script must be run as root'
fi

if [ ! -f /usr/bin/openvpn ]; then
	error 'OpenVPN must be installed for this script'
fi

if [ ! -d /etc/easy-rsa ]; then
	error 'Easy-RSA must be installed for this script'
fi

if [ ! -d /etc/easy-rsa/pki ]; then
	pushd /etc/easy-rsa >/dev/null

	info 'Configuring EasyRSA'
	echo 'set_var EASYRSA_ALGO ed' >> vars
	echo 'set_var EASYRSA_CURVE ed25519' >> vars
	echo 'set_var EASYRSA_DIGEST sha512' >> vars

	info 'Setting up PKI'
	easyrsa init-pki

	info 'Building CA certificate'
	yes | easyrsa build-ca nopass

	info 'Building server certificate'
	easyrsa build-server-full server nopass

	info 'Generating CRL'
	easyrsa gen-crl

	chown -R openvpn:network pki
	chmod 700 pki

	popd >/dev/null
fi

if [ ! -f /etc/openvpn/ta.key ]; then
	info 'Generating static TLS key'
	openvpn --genkey secret /etc/openvpn/ta.key
	chown openvpn:network /etc/openvpn/ta.key
	chmod 600 /etc/openvpn/ta.key
fi

if [ ! -f /etc/openvpn/server/server.conf ]; then
	info 'Configuring OpenVPN'

	mkdir -vp /etc/openvpn/server
	cat << ! > /etc/openvpn/server/server.conf
port 1194
proto udp
dev tun
ca /etc/easy-rsa/pki/ca.crt
cert /etc/easy-rsa/pki/issued/server.crt
key /etc/easy-rsa/pki/private/server.key
crl-verify /etc/easy-rsa/pki/crl.pem
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
tls-crypt /etc/openvpn/ta.key
cipher AES-256-GCM
user nobody
group nobody
persist-key
persist-tun
verb 3
mute 20
dh none
ecdh-curve ed25519
auth SHA512
tls-version-min 1.3
!
	chown -vR openvpn:network /etc/openvpn/server

	info 'Starting OpenVPN service'
	systemctl enable --now openvpn-server@server
fi

printf 'OpenVPN status: %s (%s)\n' \
	`systemctl status openvpn-server@server | grep --color=never -Po 'e: \K.*(?= \()'` \
	`systemctl status openvpn-server@server | grep --color=never -Po '; \K.*(?=; v)'`

cat << !
a) Add a client
r) Remove a client
l) List all valid clients
t) Stop OpenVPN server
s) Start OpenVPN server
e) Enable OpenVPN server on startup
d) Disable OpenVPN server on startup
i) View OpenVPN server logs
u) Uninstall OpenVPN server
q) Quit
!

read -p '> ' -n1 opt
echo
case $opt in
	a)
		read -p 'Client name: ' name

		info 'Generating client certificate'
		pushd /etc/easy-rsa >/dev/null
		easyrsa build-client-full $name nopass
		popd >/dev/null

		info 'Genering client .ovpn file'
		cat << ! > $name.ovpn
client
dev tun
proto udp
remote `curl -s4 ipconfig.io/ip` 1194
nobind
user nobody
group nobody
persist-key
persist-tun
mute-replay-warnings
remote-cert-tls server
cipher AES-256-GCM
auth SHA512
verb 3
mute 20
auth-nocache

<ca>
`</etc/easy-rsa/pki/ca.crt`
</ca>

<cert>
`</etc/easy-rsa/pki/issued/$name.crt`
</cert>

<key>
`</etc/easy-rsa/pki/private/$name.key`
</key>

<tls-crypt>
`</etc/openvpn/ta.key`
</tls-crypt>
!
		;;
	r)
		read -p 'Client name: ' name

		if [ ! -f /etc/easy-rsa/pki/issued/$name.crt ]; then
			error 'Client specified does not exist'
		fi

		pushd /etc/easy-rsa >/dev/null

		info 'Revoking client certificate'
		yes | easyrsa revoke $name

		info 'Generating CRL'
		easyrsa gen-crl

		info 'Removing remaining files'
		rm -vf pki/reqs/$name.req
		rm -vf pki/issued/$name.crt
		rm -vf pki/private/$name.key

		popd >/dev/null
		;;
	l)
		ls /etc/easy-rsa/pki/issued | sed 's/.crt//g' | grep -v '^server$'
		;;
	t)
		systemctl stop openvpn-server@server
		;;
	s)
		systemctl start openvpn-server@server
		;;
	e)
		systemctl enable openvpn-server@server
		;;
	d)
		systemctl disable openvpn-server@server
		;;
	i)
		journalctl -u openvpn-server@server
		;;
	u)
		info 'Stopping OpenVPN service'
		systemctl disable --now openvpn-server@server

		info 'Removing PKI'
		rm -vrf /etc/easy-rsa/pki

		info 'Removing static TLS key'
		rm -vf /etc/openvpn/ta.key

		info 'Removing server configuration'
		rm -vf /etc/openvpn/server/server.conf
		;;
esac
