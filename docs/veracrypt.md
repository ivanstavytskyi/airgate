# Encryption at rest with VeraCrypt

Optional layer. Puts both VMs inside a VeraCrypt volume so that the environment is unreadable when unmounted and can be destroyed by deleting one file.

## Why a hidden volume

A **hidden volume** lives inside the free space of an **outer volume**. Which one is opened depends on the password you enter. The outer volume can hold harmless decoy data; the hidden one holds the VMs. If you are ever forced to reveal a password, you can give the outer one. See [VeraCrypt: Hidden Volume](https://veracrypt.io/en/Hidden%20Volume.html).

If you do not need that, a **standard** volume works identically for this project — just skip the hidden-volume pages of the wizard.

## Creating the volume (as done in the README)

| # | Wizard page | Choice used |
|---|---|---|
| 1 | Volume type | Create an encrypted file container |
| 2 | Hidden / standard | Hidden VeraCrypt volume → Normal mode |
| 3 | Location | an existing empty `.hc` file, confirm replace; "Never save history" on |
| 4 | Outer encryption | AES, SHA-512 (defaults) |
| 5 | Outer size | 20 GiB (check the unit — MiB is the default) |
| 6 | Outer password | long random (e.g. KeePassXC generator, 128 chars, no special characters) |
| 7 | Outer large files | No |
| 8 | Outer format | collect entropy, Format |
| 9 | Hidden encryption | defaults |
| 10 | Hidden size | maximum offered (19 GiB) |
| 11 | Hidden password | different, strong, stored safely |
| 12 | Hidden large files | **Yes** — VM disks exceed 4 GB |
| 13 | Hidden format | Format |

Mount with the **hidden** password, drive `A:`, then create `baseline\`, `gateway\`, `sandbox\` on it.

Password screens use VeraCrypt's secure desktop and cannot be captured; for an illustrated version of the wizard follow the official [Beginner's Tutorial](https://veracrypt.io/en/Beginner%27s%20Tutorial.html).

## Sizing

- VMware disks created with *"Allocate all disk space now"* **unchecked** are thin: they grow with use. 6 GB + 14 GB nominal fits in 19 GiB as long as the guests do not actually fill up.
- Snapshots and suspend files (`.vmem` = guest RAM size) are written next to the `.vmx`, inside the volume. Budget for them or avoid suspend.
- If you outgrow the volume, create a bigger one and move the folders; VeraCrypt containers cannot be resized in place.

## Operational rules

1. **Mount first, then start VMware.** VMware must see `A:\` before you open the `.vmx` files.
2. **Power off both VMs before dismounting.** A running or suspended VM has open file handles; dismounting under it corrupts the disk image. VeraCrypt will refuse a normal dismount while files are open — do not force it.
3. **Don't keep the `.hc` file in a cloud-synced folder** while it's mounted. A sync client and VMware writing to the same 20 GB file at once will corrupt it.
4. Keep VMware's working directory inside the volume (`VM → Settings → Options → Working directory`), otherwise suspend/snapshot data can land outside the encrypted area.

## Performance

AES with AES-NI adds a few percent CPU overhead; disk throughput inside a file container is a little lower than on a raw partition. For a router VM and a browsing/analysis VM this is not noticeable. If it matters, encrypt a dedicated partition instead of using a file container.

## Host-side leftovers

VeraCrypt protects the volume. It does not protect:

- **Host swap / pagefile / hibernation file**, which can contain guest memory pages while the VM runs.
- **VMware logs** in the host's temp/AppData folders (file names, paths).

Encrypt the host system disk (BitLocker/LUKS) if those matter to you.

## Destroying the environment

Power off VMs → dismount → delete the `.hc` file. Without the password the freed blocks are indistinguishable from random data. For SSDs, secure deletion is a longer topic; treat "delete the container" as "unreadable", not "physically erased".
