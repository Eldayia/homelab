#!/usr/bin/env bash

set -Eeuo pipefail

CONNECTION="${NM_CONNECTION:-netplan-eth0}"
HOST_NAME="${HOST_NAME:-rpi4}"
ADDRESS="${LAN_ADDRESS:-192.168.1.240/24}"
GATEWAY="${LAN_GATEWAY:-192.168.1.1}"
DNS_SERVERS="${LAN_DNS_SERVERS:-192.168.1.240,194.242.2.5,1.1.1.1}"
APPLY=0

[[ "${1:-}" == "--apply" ]] && APPLY=1

if ((EUID != 0)); then
  exec sudo -E bash "$0" "$@"
fi

command -v nmcli >/dev/null || {
  echo "NetworkManager/nmcli est requis." >&2
  exit 1
}
nmcli connection show "$CONNECTION" >/dev/null

cat <<EOF
Configuration prévue:
  connexion : $CONNECTION
  hostname  : $HOST_NAME
  IPv4      : $ADDRESS
  passerelle: $GATEWAY
  DNS       : $DNS_SERVERS
EOF

if ((!APPLY)); then
  echo "Aucune modification. Relancer avec --apply depuis une console ou en gardant une seconde session SSH ouverte."
  exit 0
fi

hostnamectl set-hostname "$HOST_NAME"
timedatectl set-timezone Europe/Paris
localectl set-locale LANG=en_GB.UTF-8
localectl set-x11-keymap fr pc105

nmcli connection modify "$CONNECTION" \
  ipv4.method manual \
  ipv4.addresses "$ADDRESS" \
  ipv4.gateway "$GATEWAY" \
  ipv4.dns "$DNS_SERVERS" \
  ipv4.ignore-auto-dns yes \
  ipv6.method auto

echo "Activation de la connexion; la session SSH peut être interrompue."
nmcli connection up "$CONNECTION"
