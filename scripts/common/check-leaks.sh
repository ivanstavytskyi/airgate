#!/usr/bin/env bash
# Quick leak check. Run inside the sandbox (or on the gateway to compare).
# Prints: default route, public IPv4, whether IPv6 is reachable (it must NOT be),
# the resolvers in use, and a DNS resolution test.
set -uo pipefail

T=6  # seconds timeout per request

echo "== Routes"
ip -4 route show default || echo "(no IPv4 default route)"
ip -6 route show default 2>/dev/null | grep -q . && echo "WARNING: IPv6 default route present" || echo "IPv6 default route: none (good)"

echo
echo "== Public IPv4"
ip4=$(curl -4 -s --max-time "$T" https://ifconfig.me || true)
[[ -n "$ip4" ]] && echo "$ip4" || echo "no IPv4 connectivity (if the VPN is down on the gateway this is the kill-switch working)"

echo
echo "== Public IPv6 (should fail)"
ip6=$(curl -6 -s --max-time "$T" https://ifconfig.me 2>/dev/null || true)
[[ -n "$ip6" ]] && echo "WARNING: IPv6 reachable: $ip6" || echo "unreachable (good)"

echo
echo "== Resolvers"
if command -v resolvectl >/dev/null 2>&1; then
    resolvectl status 2>/dev/null | grep -E "DNS Servers|Current DNS" || true
fi
grep -E '^nameserver' /etc/resolv.conf || true

echo
echo "== DNS resolution"
if getent hosts debian.org >/dev/null 2>&1; then
    echo "debian.org resolves (via configured resolver, through the tunnel)"
else
    echo "resolution failed"
fi

echo
echo "For a full check open in a browser: https://2ip.io  and  https://dnsleaktest.com"
