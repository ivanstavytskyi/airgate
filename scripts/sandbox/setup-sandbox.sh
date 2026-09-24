#!/usr/bin/env bash
# Configure the sandbox VM: static IP on the LAN segment, default gateway = gateway VM,
# DNS via the gateway/tunnel, IPv6 disabled.
#
# Run as root inside the sandbox VM:  su -  &&  bash scripts/sandbox/setup-sandbox.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: su -"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.env
source "${SCRIPT_DIR}/../config.env"

if ! nmcli -t -f NAME connection show | grep -qxF "${CLIENT_CON}"; then
    echo "Connection '${CLIENT_CON}' not found. Available connections:"
    nmcli connection show
    echo "Set CLIENT_CON in config.env and re-run."
    exit 1
fi

echo "==> ${CLIENT_IFACE}: ${CLIENT_IP}/${PREFIX} via ${GATEWAY_IP}, DNS ${DNS}, IPv6 off"
nmcli connection modify "${CLIENT_CON}" \
    connection.interface-name "${CLIENT_IFACE}" \
    ipv4.method manual \
    ipv4.addresses "${CLIENT_IP}/${PREFIX}" \
    ipv4.gateway "${GATEWAY_IP}" \
    ipv4.dns "${DNS}" \
    ipv4.ignore-auto-dns yes \
    ipv6.method disabled
nmcli connection up "${CLIENT_CON}"

echo
echo "==> Done. Verify:"
echo "    ip -br a && ip route"
echo "    ping -c 3 ${GATEWAY_IP}"
echo "    bash $(dirname "${SCRIPT_DIR}")/common/check-leaks.sh"
