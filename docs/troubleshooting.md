# Troubleshooting

Work top-down: hypervisor wiring → gateway → sandbox.

## Sandbox cannot ping 10.10.10.1

- Both VMs must be on the **same LAN segment name** (`sandbox-lan`). Check *Settings → Network Adapter* on both. A segment with a typo is a different, empty network.
- On the gateway: `ip -br a` must show `ens37` with `10.10.10.1/24` and state `UP`. If not, `nmcli connection up lan`.
- Interface names differ from `ens33`/`ens37`? Update `scripts/config.env` and re-run the scripts. Adapter 2 is often `ens37` in VMware but can be `ens38`/`ens34` depending on slot.
- On the sandbox: `ip route` must show `default via 10.10.10.1 dev ens33`. If NetworkManager still runs DHCP, `nmcli connection show` and make sure you modified the connection that is actually active.

## Sandbox pings the gateway but has no internet

1. Is the VPN up on the gateway? `ip -br a | grep amn0` (or `wg0`). If the interface is missing, the kill-switch is doing its job — connect the VPN.
2. `sysctl net.ipv4.ip_forward` must be `1`.
3. `nft list ruleset` must show the forward chain with the two accept rules and the masquerade rule. If empty: `systemctl status nftables`, `nft -c -f /etc/nftables.conf`.
4. `ip r get 1.1.1.1 from 10.10.10.2 iif ens37` must say `dev amn0`. If it says `dev ens33`, the VPN client did not install a default route into the tunnel (check *AllowedIPs = 0.0.0.0/0* / split tunneling disabled).

## Sandbox has internet even with the VPN disconnected

That is a leak. Causes seen in practice:

- `nftables` not loaded or policy not `drop`: `nft list chain inet filter forward`.
- A rule forwarding `ens37 → ens33` was added by hand or by another tool. Remove it.
- The VPN client left a stale interface named `amn0` that now routes to the WAN. Reboot the gateway or restart the client.

## DNS does not resolve on the sandbox

- `cat /etc/resolv.conf` on the sandbox should contain `nameserver 1.1.1.1` (or whatever `DNS` you set). If it shows the VMware NAT resolver (`192.168.x.2`), the connection still had `ipv4.ignore-auto-dns no`; re-run `setup-sandbox.sh`.
- `dig @1.1.1.1 debian.org` from the sandbox — if this works but plain `dig debian.org` does not, it is a resolver-config problem, not a routing problem.
- Some VPN endpoints block outbound port 53 to third-party resolvers. Use the provider's DNS as `DNS` in `config.env`.

## DNS leak test shows my ISP's resolver

The query is not going through the gateway. Check the sandbox is not somehow multi-homed (`ip -br a` — exactly one non-loopback interface). Confirm IPv6 is disabled on the sandbox (`ip -6 addr` shows nothing but `::1`).

## AmneziaVPN connects but `amn0` has a different name

Look it up: `ip -br link`. Set `VPN_IFACE` accordingly and re-run `setup-gateway.sh`.

## "connection 'Wired connection 1' not found"

NetworkManager named the profile differently (localised systems, or `netplan`-style names). `nmcli connection show`, then set `WAN_CON` / `CLIENT_CON` in `config.env`.

## VMware: LAN segment option greyed out

Power the VM off. LAN segment assignment cannot be changed on a running or suspended VM.

## VeraCrypt: "cannot dismount, volume contains files in use"

A VM is still running or suspended, or VMware Workstation still holds a lock. Power off all VMs from the volume and close Workstation, then dismount. Do not force-dismount.

## Gateway lost its own internet after running the script

`setup-gateway.sh` only touches the `lan` connection and the DNS of `WAN_CON`. If `WAN_CON` pointed to the wrong profile, restore with:

```bash
nmcli connection modify "<name>" ipv4.ignore-auto-dns no ipv4.dns ""
nmcli connection up "<name>"
```
