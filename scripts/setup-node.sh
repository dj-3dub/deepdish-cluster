#!/usr/bin/env bash
# Usage: sudo ./setup-node.sh <hostname> <ip> [iface=ens34] [gw=192.168.2.1] [dns1=192.168.2.51] [dns2=1.1.1.1] [user=tim]
set -euo pipefail
HN="${1:-}"; IP="${2:-}"
IFACE="${3:-ens34}" ; GW="${4:-192.168.2.1}"
DNS1="${5:-192.168.2.51}" ; DNS2="${6:-1.1.1.1}"
USER_NAME="${7:-tim}"

[[ -z "$HN" || -z "$IP" ]] && { echo "Usage: sudo $0 <hostname> <ip> [iface] [gw] [dns1] [dns2] [user]"; exit 1; }

echo "[*] Setting hostname -> $HN"
hostnamectl set-hostname "$HN"

echo "[*] Ensuring sudo + adding $USER_NAME to sudo group"
apt-get update -y
apt-get install -y sudo
id -nG "$USER_NAME" | grep -qw sudo || usermod -aG sudo "$USER_NAME"

echo "[*] Configuring static IP on $IFACE -> $IP"
mkdir -p /etc/network/interfaces.d
cat >/etc/network/interfaces.d/"$IFACE" <<EOF
auto $IFACE
iface $IFACE inet static
    address $IP/24
    gateway $GW
    dns-nameservers $DNS1 $DNS2
EOF

systemctl restart networking
ip -brief addr show "$IFACE"
echo "[*] Done. Try: ssh $USER_NAME@$IP"
