# ovpnmgr

Script for configuring an OpenVPN server & clients.

## Features

* Configures OpenVPN and Easy-RSA.
* Create `.ovpn` files for clients to connect.
* Can revoke/delete clients so they won't work anymore.
* Utilities for managing the OpenVPN service.
* Secure & modern cryptography used by default.
* Configured for high performance.

## Notes

* Uses AES-256-GCM/SHA512 for encryption.
* Uses TLSv1.3 for the control channel.
* Uses tls-crypt to prevent port-scanning and probing.
* Runs on port 1194, protocol UDP by default.

## Requirements

* OpenVPN 2.4+
* OpenSSL 1.1.1+
* Easy-RSA 3.0+

Installing the above packages can be done on Arch like this:

```sh
pacman -S --needed openssl openvpn easy-rsa
```

## Deployment

Everything is contained in one shell script. The first time it is ran, it
will begin to setup and configure the OpenVPN server. Run it again whenever
you want to add/delete clients or uninstall OpenVPN from your server.

```sh
curl -LO https://raw.githubusercontent.com/asineth0/ovpnmgr/master/ovpnmgr.sh
chmod +x ovpnmgr.sh
sudo ./ovpnmgr.sh
```
