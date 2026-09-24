<div align="center">

# Disposable Sandbox Gateway

**A throwaway lab on your own computer that can't leak your IP address.**

Two VMware virtual machines. One is where you work. The other is a small router that only lets traffic out through an encrypted tunnel. If the tunnel drops, the sandbox goes offline instead of falling back to your real connection.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-VMware%20Workstation-607078)
![Guest OS](https://img.shields.io/badge/guest-Debian%2013-A81D33)
![Tunnel](https://img.shields.io/badge/tunnel-WireGuard%20%2F%20AmneziaWG-88171A)

[Why it exists](#why-it-exists) ·
[How it works](#how-it-works) ·
[What you need](#what-you-need) ·
[Set it up](#set-it-up) ·
[Check for leaks](#step-6--check-for-leaks) ·
[Everyday use](#everyday-use) ·
[Double VPN](#double-vpn-a-second-hop-inside-the-sandbox) ·
[Docs](#documentation) ·
[License](#license)

</div>

---

## Why it exists

You're testing untrusted software, or running an authorized penetration test, and you want an environment that:

- runs locally, on your own machine;
- shows none of your host's fingerprints — not the IP address, not the MAC address, not the hardware;
- can't leak through DNS, IPv6, or a VPN app that quietly stopped running;
- can be reset in seconds, or destroyed completely when the job is done;
- can grow into a [double VPN](#double-vpn-a-second-hop-inside-the-sandbox) by simply starting a second client in the sandbox.

Putting a VPN client inside a single VM doesn't get you there. The moment that client crashes, gets killed, or is bypassed by a route change, the VM falls back to your host's network and your real IP address goes out.

This project fixes that by moving the VPN one machine *away* from where the untrusted code runs. The sandbox has exactly one way out — a second VM acting as its router — and that router refuses to forward anything that isn't going into the tunnel. The rule lives in the kernel of a machine the sandbox can't touch.

The design borrows the gateway + workstation idea from [Whonix](https://www.whonix.org/), but stays small: stock Debian, NetworkManager, one `nftables` file, and whichever VPN client you prefer.

## How it works

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="images/diagrams/topology-dark.png">
    <img alt="Topology: sandbox VM on a LAN segment, gateway VM with NAT uplink and tunnel, VPN server, internet" src="images/diagrams/topology.png">
  </picture>
</p>

- **sandbox** — a normal Debian desktop. Its only network adapter sits on a VMware *LAN segment* — a private wire that exists only inside VMware. Its default route points at the gateway. That's all it knows about.
- **gateway** — a second Debian VM with two adapters: one on the same LAN segment, one on VMware NAT for its own uplink. It runs the VPN client and a short `nftables` ruleset that forwards packets from the LAN segment **only** into the tunnel interface. There is no rule that forwards them to the host NAT adapter.
- **tunnel** — WireGuard by default, via the [AmneziaVPN](https://amnezia.org/) client. OpenVPN, AmneziaWG, WARP or anything else that creates a tunnel interface works the same way.

### What happens when the tunnel drops

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="images/diagrams/tunnel-down-dark.png">
    <img alt="Sequence: with the tunnel up traffic is forwarded into amn0; with the tunnel down the forward chain drops it" src="images/diagrams/tunnel-down.png">
  </picture>
</p>

Nothing in the sandbox can change this outcome. The sandbox can't reach the host network, and it can't edit the gateway's firewall.

### Compared with a VPN client inside the sandbox

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="images/diagrams/comparison-dark.png">
    <img alt="Single VM with a VPN app falls back to host NAT; with a separate gateway traffic is dropped instead" src="images/diagrams/comparison.png">
  </picture>
</p>

| | VPN app inside the sandbox | Separate gateway VM |
|---|---|---|
| VPN app stops or crashes | traffic falls back to host NAT | no route exists — traffic is dropped |
| Malware edits routes or kills the VPN | works — leaks your IP | one next hop only, gateway still refuses to forward to NAT |
| DNS | depends on the app's settings | all DNS travels sandbox → gateway → tunnel |
| IPv6 | must be turned off in the guest | no IPv6 on the LAN segment; forward chain allows tunnel only |
| Host fingerprint | VM has its own MAC | same, and the sandbox never sees the host's network at all |

More on the design and the threat model: [`docs/architecture.md`](docs/architecture.md).

## What you need

- **VMware Workstation Pro 17.x** (Player works too — LAN segments are available in both).
- **Debian 13 netinst ISO** — [debian.org/download](https://www.debian.org/download).
- A **WireGuard or AmneziaWG config** from your own server or a provider you trust.
- About **20 GB** of disk and **8 GB+** of RAM on the host.
- *(Optional)* [VeraCrypt](https://veracrypt.io/) if you want the whole lab encrypted at rest.

Resources used in this guide — adjust to your host:

| VM | vCPU | RAM | Disk | Adapters |
|---|---|---|---|---|
| `gateway` | 4 | 4 GB | 6 GB | NAT + `sandbox-lan` |
| `sandbox` | 8 | 8 GB | 14 GB | `sandbox-lan` only |

Disks are thin-provisioned, so 6 + 14 GB fits comfortably in a 19 GiB volume.

## Set it up

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="images/diagrams/setup-steps-dark.png">
    <img alt="Setup roadmap: steps 0-2 on the host, steps 3-6 inside the guests" src="images/diagrams/setup-steps.png">
  </picture>
</p>

Steps 0–2 happen in Windows and VMware (screenshots). Steps 3–6 happen inside the guests (commands and scripts).

### Step 0 — Encrypted volume (optional)

Skip this if you don't need encryption at rest: create a folder for the VMs on any disk and go to Step 1.

The goal is a VeraCrypt **hidden volume**, mounted as drive `A:`, with three folders inside.

![VeraCrypt container file](images/00-veracrypt-01-container-file.jpg)

1. Create an empty file with the `.hc` extension, for example `C:\encrypted\volume.hc`.
2. Open VeraCrypt → **Create Volume** → **Create an encrypted file container** → **Hidden VeraCrypt volume** → **Normal mode**.
3. **Volume location**: pick the `.hc` file, confirm replacing it. Leave *Never save history* checked.
4. **Outer volume encryption**: keep the defaults, `AES` and `SHA-512`.
5. **Outer volume size**: `20 GiB`. Check the unit — the drop-down defaults to MiB.
6. **Outer volume password**: something long and random. A password manager's generator works well (KeePassXC: *Tools → Password Generator*, 128 characters, special characters off so nothing needs escaping). The outer volume holds no sensitive data, so you can store this password less strictly.
7. *Large files?* → **No**. Move your mouse to collect entropy → **Format**.
8. VeraCrypt moves on to the **hidden volume**. Keep the same encryption defaults.
9. **Hidden volume size**: the maximum offered — here `19 GiB`.
10. **Hidden volume password**: a different strong password. This is the one that matters; keep it somewhere safe.
11. *Large files?* → **Yes**, because VM disks are bigger than 4 GB. **Format**.
12. Mount: select the `.hc` file, choose drive `A:`, click **Mount**, enter the **hidden** password.

> VeraCrypt's password dialogs run on a secure desktop and can't be captured, which is why there are no screenshots of them here. The official [Beginner's Tutorial](https://veracrypt.io/en/Beginner%27s%20Tutorial.html) shows every page.

Inside `A:\` create three folders and copy the Debian ISO into the first one:

```text
A:\
├── baseline\   ← debian-13.x.x-amd64-netinst.iso
├── gateway\
└── sandbox\
```

**Always power off both VMs before you dismount the volume.** Dismounting under a running or suspended VM corrupts its disk. Details and caveats: [`docs/veracrypt.md`](docs/veracrypt.md).

### Step 1 — Create the two VMs

The wizard is shown once, for `gateway`. Then repeat it for `sandbox` with the differences listed at the end.

**VMware Workstation → File → New Virtual Machine…**

| Page | Choose |
|---|---|
| Configuration type | **Custom (advanced)** |
| Hardware compatibility | the newest — **Workstation 17.5.x** |
| Guest OS installation | **I will install the operating system later** |
| Guest OS | **Linux → Debian 12.x 64-bit** (13 isn't in the list yet; this only affects the label) |
| Name and location | `Gateway` → `A:\gateway` |
| Processors | 1 × 4 cores |
| Memory | 4096 MB |
| Network type | **NAT** — this becomes Network Adapter 1, the gateway's uplink |
| I/O controller | LSI Logic (recommended) |
| Disk type | SCSI (recommended) |
| Disk | **Create a new virtual disk** |
| Capacity | **6 GB**, *Store virtual disk as a single file* |
| Disk file | `Gateway.vmdk` |
| Summary | **Finish** |

<details>
<summary>Every wizard page as a screenshot</summary>

![Custom](images/01-vm-01-wizard-custom.jpg)
![Compatibility](images/01-vm-02-hardware-compat.jpg)
![Install later](images/01-vm-03-install-os-later.jpg)
![Guest OS](images/01-vm-04-guest-os.jpg)
![Name and location](images/01-vm-05-name-location.jpg)
![CPU](images/01-vm-06-cpu.jpg)
![Memory](images/01-vm-07-memory.jpg)
![NAT](images/01-vm-08-network-nat.jpg)
![I/O controller](images/01-vm-09-io-controller.jpg)
![Disk type](images/01-vm-10-disk-type.jpg)
![New disk](images/01-vm-11-new-disk.jpg)
![Capacity](images/01-vm-12-disk-capacity.jpg)
![Disk file](images/01-vm-13-disk-file.jpg)
![Summary](images/01-vm-14-summary.jpg)

</details>

The new VM shows up in the library, powered off:

![Created](images/01-vm-15-created.jpg)

**Attach the ISO and install Debian.** Open **Edit virtual machine settings → CD/DVD (SATA)**, select **Use ISO image file**, browse to `A:\baseline\debian-13.x.x-amd64-netinst.iso`, tick **Connect at power on**, click OK.

![CD/DVD before](images/01-vm-16-cddvd-default.jpg)
![CD/DVD with ISO](images/01-vm-17-cddvd-iso.jpg)

Power on, pick **Graphical install**, and run through a standard Debian setup. It takes 5–10 minutes. A lightweight desktop on the gateway is handy for the AmneziaVPN window; the sandbox can have whatever you like.

**Now repeat for `sandbox`**, changing only:

- name `Sandbox`, location `A:\sandbox`;
- CPU and RAM as your host allows (8 cores, 8 GB here);
- disk **14 GB**;
- network type: leave **NAT** for now — you'll switch it in Step 2.

When both installs finish, **take a snapshot of each VM** (`VM → Snapshot → Take Snapshot`, call it `clean-install`). You'll come back to it.

### Step 2 — Wire the VMs together

Both VMs powered **off**.

**Gateway — add a second adapter on a LAN segment.** Open **Edit virtual machine settings**. Network Adapter 1 is the NAT uplink; leave it as it is.

![Adapter 1 NAT](images/02-net-01-gateway-adapter1-nat.jpg)

Click **Add…** at the bottom of the device list → **Network Adapter** → **Finish**.

![Add hardware](images/02-net-02-add-network-adapter.jpg)

Select the new **Network Adapter 2** and click **LAN Segments…**

![Adapter 2](images/02-net-03-adapter2-lan-segments-button.jpg)

In the *Global LAN Segments* dialog click **Add**, name it **`sandbox-lan`**, click OK. Back in the adapter pane choose **LAN segment: `sandbox-lan`** and click OK.

![Adapter 2 on sandbox-lan](images/02-net-04-adapter2-sandbox-lan.jpg)

The gateway now has two adapters: `NAT` and `sandbox-lan`.

**Sandbox — move its only adapter to the LAN segment.** **Edit virtual machine settings → Network Adapter → LAN segment: `sandbox-lan`** → OK.

![Sandbox on sandbox-lan](images/02-net-05-sandbox-adapter-sandbox-lan.jpg)

The sandbox now has one adapter, on `sandbox-lan`. From here on it has no path to the internet until the gateway is configured. That's the point.

### Step 3 — Gateway: VPN client

Boot `gateway`. It has internet through NAT.

1. Download the Linux installer from [amnezia.org](https://amnezia.org/) or the [GitHub releases](https://github.com/amnezia-vpn/amnezia-client/releases) and install it.
2. Open **AmneziaVPN** and click *Let's get started*.

   ![Amnezia welcome](images/03-vpn-01-amnezia-welcome.jpg)

3. Choose **File with connection settings** and import your WireGuard `.conf`.

   ![Import options](images/03-vpn-02-amnezia-import-options.jpg)

   > The example uses a free Proton VPN WireGuard config. For real work, run your own WireGuard or AmneziaWG server — it takes minutes, and only you and your server see the traffic — or use a paid provider's config.

4. **Connect.** The client shows *Connected* with the protocol and endpoint.

   ![Connected](images/03-vpn-03-amnezia-connected.jpg)

5. Open a browser **on the gateway** and check your public IP at [2ip.io](https://2ip.io). It should be the VPN's address, not your ISP's.

   ![Gateway IP check](images/03-vpn-04-gateway-ip-check.jpg)

6. In **Settings → Application** turn on **Auto start**, **Auto connect** and **Start minimized**, so the tunnel comes up on boot without you clicking anything.

   ![Autostart](images/03-vpn-05-amnezia-autostart.jpg)

### Step 4 — Gateway: routing and firewall

Still on `gateway`. First, find out what your interfaces are called:

```bash
ip -br a
ip route
nmcli device status
```

Typically: `ens33` is Adapter 1 (NAT, has a `192.168.x.x` address), `ens37` is Adapter 2 (the LAN segment, no address yet), and `amn0` is the AmneziaVPN tunnel, present while connected.

Copy the `scripts/` folder into the VM (shared folder, `scp`, USB — whatever is easiest). Open [`scripts/config.env`](scripts/config.env) and fix the names if yours differ:

```bash
# gateway
WAN_IFACE="ens33"              # NAT uplink to the host
LAN_IFACE="ens37"              # LAN segment towards the sandbox
VPN_IFACE="amn0"               # tunnel interface created by the VPN client
WAN_CON="Wired connection 1"   # NetworkManager name of the WAN connection

LAN_SUBNET="10.10.10.0/24"
GATEWAY_IP="10.10.10.1"
CLIENT_IP="10.10.10.2"
PREFIX="24"
DNS="1.1.1.1"

# sandbox
CLIENT_IFACE="ens33"
CLIENT_CON="Wired connection 1"
```

Run the gateway script as root:

```bash
su -
bash scripts/gateway/setup-gateway.sh
```

[`setup-gateway.sh`](scripts/gateway/setup-gateway.sh) does six things:

1. Installs `nftables`.
2. Creates a NetworkManager connection `lan` on `ens37`: static `10.10.10.1/24`, no default route, IPv6 off.
3. Turns on `net.ipv4.ip_forward=1`, persistently.
4. Writes `/etc/nftables.conf`:

   ```nft
   table inet filter {
       chain forward {
           type filter hook forward priority 0; policy drop;
           iifname "ens37" oifname "amn0" accept
           iifname "amn0" oifname "ens37" ct state established,related accept
       }
   }
   table ip nat {
       chain postrouting {
           type nat hook postrouting priority 100;
           oifname "amn0" masquerade
       }
   }
   ```

   Forwarded traffic may go **only** from `sandbox-lan` into the tunnel, and replies may come back. There is deliberately no `ens37 → ens33` rule. When `amn0` disappears, forwarding stops.

5. Pins the gateway's own DNS on the WAN connection to `1.1.1.1` so it doesn't use the VMware NAT resolver.
6. Enables and starts `nftables`.

The rendered ruleset is in [`config/nftables.conf.example`](config/nftables.conf.example).

Confirm that a packet from the sandbox would enter the tunnel:

```bash
ip r get 1.1.1.1 from 10.10.10.2 iif ens37
# expect: ... dev amn0 ...
```

### Step 5 — Sandbox: point it at the gateway

Boot `sandbox`, copy `scripts/` in, then as root:

```bash
su -
bash scripts/sandbox/setup-sandbox.sh
```

[`setup-sandbox.sh`](scripts/sandbox/setup-sandbox.sh) gives the one adapter a static address. It's the same as running:

```bash
nmcli connection modify "Wired connection 1" \
  ipv4.method manual \
  ipv4.addresses 10.10.10.2/24 \
  ipv4.gateway 10.10.10.1 \
  ipv4.dns 1.1.1.1 \
  ipv6.method disabled
nmcli connection up "Wired connection 1"
```

No DHCP. The sandbox can only ever talk to `10.10.10.1`.

### Step 6 — Check for leaks

On the **sandbox**:

```bash
ip -br a            # ens33 = 10.10.10.2/24, no IPv6 address
ip route            # default via 10.10.10.1
ping -c 3 10.10.10.1
bash scripts/common/check-leaks.sh
```

Then in a browser on the sandbox:

- **Public IP** — [2ip.io](https://2ip.io) or [ifconfig.me](https://ifconfig.me). It must match the VPN address you saw on the gateway.

  ![Sandbox IP](images/05-verify-01-sandbox-ip.jpg)

- **DNS leak test** — [dnsleaktest.com](https://dnsleaktest.com) or [astrill.com/dns-leak-test](https://www.astrill.com/dns-leak-test). Only the resolver you configured (`1.1.1.1` → Cloudflare) should show up. Your ISP's resolvers must not.

  ![Sandbox DNS](images/05-verify-02-sandbox-dns-leak.jpg)

- **Tunnel-down test** — on the gateway, disconnect the VPN in AmneziaVPN. On the sandbox, `ping 1.1.1.1` and the browser must stop working right away. Reconnect, and traffic comes back. If the sandbox still has internet with the VPN disconnected, the forward chain isn't loaded — see [`docs/troubleshooting.md`](docs/troubleshooting.md).

Passed? **Snapshot both VMs again** and call it `configured`.

## Everyday use

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="images/diagrams/lifecycle-dark.png">
    <img alt="Snapshot lifecycle: clean-install, configured, working session, new identity, destroyed" src="images/diagrams/lifecycle.png">
  </picture>
</p>

- **Fresh session** — revert `sandbox` to `configured`. Everything from the last session is gone; the gateway is untouched.
- **New identity** — import a different WireGuard config on the gateway, reconnect, run Step 6 again.
- **Burn it** — power off both VMs, dismount the VeraCrypt volume, delete the `.hc` file. Without VeraCrypt, delete the `gateway\` and `sandbox\` folders.
- **Rebuild** — mount or create a volume, restore the `clean-install` snapshots or repeat Steps 1–5. The in-guest part takes about a minute with the scripts.

## Double VPN: a second hop inside the sandbox

Because everything the sandbox sends is already forced through the gateway's tunnel, any VPN client or proxy you start **inside the sandbox** automatically becomes a second hop. No extra routing or firewall work — it just nests.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="images/diagrams/double-vpn-dark.png">
    <img alt="Double VPN chain: sandbox hop-2 client, gateway hop-1 client, ISP, hop 1, hop 2, destination" src="images/diagrams/double-vpn.png">
  </picture>
</p>

### Who sees what

| Party | Sees | Does not see |
|---|---|---|
| **Your ISP** | encrypted WireGuard traffic from your IP to hop 1 | destinations, content, that a second tunnel exists |
| **Hop 1** — your VPN server or its hosting provider | your real IP | where the traffic goes or what's in it — it's still wrapped in the hop-2 tunnel |
| **Hop 2** — the VPN or proxy provider used in the sandbox | destinations and (TLS-encrypted) requests | your real IP — it only sees hop 1's exit address |
| **Destination** | hop 2's IP address | anything about you, hop 1, or your ISP |

Two parties would have to cooperate to connect you to your traffic. If hop 1 is a server you rent yourself, its hosting provider knows a VPS you pay for made an encrypted connection somewhere — and nothing more.

### Why the gateway makes this safer than a normal double VPN

Chaining two VPN apps on one machine has the same weak spot as one: if the outer client dies, everything falls back to your real connection. Here the outer hop is on the gateway, behind the `nftables` rule. If the hop-2 client in the sandbox crashes, traffic simply continues through hop 1 — still not your IP. If hop 1 drops, the sandbox goes offline. **Your real IP is never the fallback.**

### What to run as hop 2

Anything that works on a regular Debian desktop:

- **A second WireGuard / AmneziaVPN / OpenVPN client** with a different provider than hop 1.
- **Tor Browser** — Tor over VPN, with the entry guard seeing hop 1's IP instead of yours.
- **A SOCKS5 or HTTP proxy**, or an `ssh -D` tunnel to a server you control — lighter, and enough when you only need a different exit for a browser.
- **A provider's own multi-hop feature** — works too, but then both hops belong to the same company.

### Trade-offs

- **Speed.** Two layers of encryption and two extra round trips. Expect roughly half the throughput and 30–100 ms more latency, depending on where the hops are.
- **MTU.** A WireGuard tunnel inside a WireGuard tunnel needs a smaller packet size or you'll see stalls on large downloads. Set `MTU = 1280` in the hop-2 config on the sandbox.
- **Blocking.** Some providers detect and refuse nested VPN traffic or block other providers' address ranges. If hop 2 won't connect through hop 1, try another server on either side.
- **DNS.** While hop 2 is up, its DNS applies. If it drops, the sandbox falls back to the resolver from `config.env`, still through hop 1. Rerun Step 6 after you set up hop 2 to confirm.
- **Choose different providers.** Two hops through the same company is one hop with extra latency.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — threat model, why the enforcement point is on a separate VM, what's out of scope.
- [`docs/veracrypt.md`](docs/veracrypt.md) — hidden volumes, sizing, mount/dismount rules, what VeraCrypt does *not* protect.
- [`docs/hardening.md`](docs/hardening.md) — optional extras: `wg-quick` instead of the GUI, IPv6 off on the WAN, stricter input rules, forced DNS, random MAC addresses.
- [`docs/troubleshooting.md`](docs/troubleshooting.md) — symptoms and fixes, top-down from VMware to the guests.

Repository layout:

```text
.
├── README.md
├── LICENSE                         MIT
├── docs/                           the four documents above
├── images/                         screenshots, prefixed by step: 00-veracrypt, 01-vm, 02-net, 03-vpn, 05-verify
│   └── diagrams/                   diagrams, light and dark variants
├── scripts/
│   ├── config.env                  interfaces, subnet, DNS — the only file you should need to edit
│   ├── gateway/setup-gateway.sh    forwarding, nftables, static LAN address, DNS pin
│   ├── sandbox/setup-sandbox.sh    static address, default route to the gateway, IPv6 off
│   └── common/check-leaks.sh       public IP, IPv6 reachability, resolvers
└── config/
    ├── nftables.conf.example       the rendered ruleset
    └── wg0.conf.example            WireGuard client template for wg-quick users
```

## Limitations

- **Application-layer leaks** — WebRTC, browser fingerprinting, logged-in accounts — are not solved by network isolation. Harden the browser inside the sandbox separately.
- **The gateway itself** is not behind the firewall. Its own traffic — the VPN handshake — legitimately leaves through NAT. Don't do your work on the gateway.
- **Host swap and pagefile** can hold VM memory while a VM runs. Encrypt the host system disk if that matters.
- **VM escape** and hypervisor bugs are out of scope.
- Tested on a Windows host with VMware Workstation Pro 17.5 and Debian 13 (trixie) guests using NetworkManager. Other combinations may need different interface or connection names in `config.env`.

## Contributing

Issues and pull requests are welcome. If you've run this on a different host OS, hypervisor or VPN client, a short note in the troubleshooting doc helps the next person.

## Disclaimer

This project is for **authorized** security testing, malware analysis in controlled environments, and privacy research. Only test systems you own or have explicit written permission to test. The authors accept no responsibility for misuse.

## License

[MIT](LICENSE)
