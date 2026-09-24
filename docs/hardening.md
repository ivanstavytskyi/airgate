# Optional hardening

Everything in the README is what was built and verified. The items below are extras you can add; none are required for the kill-switch to work.

## 1. wg-quick instead of the AmneziaVPN GUI

A headless gateway has a smaller footprint and comes up without a desktop session.

```bash
# gateway
apt install wireguard
cp config/wg0.conf.example /etc/wireguard/wg0.conf   # fill in real values
chmod 600 /etc/wireguard/wg0.conf
systemctl enable --now wg-quick@wg0
```

Then set `VPN_IFACE="wg0"` in `scripts/config.env` and re-run `setup-gateway.sh`. For AmneziaWG use `awg-quick` and the `amneziawg` packages; the interface name is whatever you call the config file.

## 2. Disable IPv6 on the gateway WAN too

The forward chain already refuses IPv6 egress to anything but the tunnel, and VMware NAT normally offers no IPv6. If you'd rather not rely on either, turn it off:

```bash
# gateway
nmcli connection modify "Wired connection 1" ipv6.method disabled
nmcli connection up "Wired connection 1"
```

## 3. Stricter input rules on the gateway

By default the gateway accepts any inbound connection from the sandbox to itself (SSH, etc.). To let the sandbox use the gateway *only* as a router:

```nft
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        iif "lo" accept
        ct state established,related accept
        # allow ping from sandbox for diagnostics, nothing else
        iifname "ens37" icmp type echo-request accept
        # keep host-side access to the gateway (adjust to taste)
        iifname "ens33" accept
    }
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
```

Merge into `/etc/nftables.conf` and reload (`nft -c -f` first).

## 4. Force sandbox DNS to a fixed resolver

The sandbox already uses a static resolver (`1.1.1.1`) that is reached through the tunnel. To stop any process in the sandbox from picking a different one, redirect all DNS on the gateway:

```nft
table ip nat {
    chain prerouting {
        type nat hook prerouting priority -100;
        iifname "ens37" udp dport 53 dnat to 1.1.1.1
        iifname "ens37" tcp dport 53 dnat to 1.1.1.1
    }
}
```

## 5. Block sandbox → gateway management traffic from the sandbox side

Alternatively or additionally, on the sandbox itself, drop everything that is not going to the default gateway MAC/IP. Rarely needed; the gateway rules above are the right place.

## 6. Randomise MAC addresses

VMware assigns a stable MAC per VM. If you want a different one each session, set in the `.vmx`:

```text
ethernet0.addressType = "generated"
```

and remove the `ethernet0.generatedAddress*` lines before booting. On the sandbox side you can also let NetworkManager randomise: `nmcli connection modify "Wired connection 1" ethernet.cloned-mac-address random`.

## 7. Browser inside the sandbox

Network isolation does not cover WebRTC or fingerprinting. Use a hardened browser profile (e.g. Firefox with `media.peerconnection.enabled=false`, resist-fingerprinting on) or Tor Browser inside the sandbox.

## 8. Snapshots as policy

- `clean-install` snapshot right after Debian is installed.
- `configured` snapshot after Step 6 passes.
- Revert `sandbox` to `configured` before every new task. Never carry state between engagements.
