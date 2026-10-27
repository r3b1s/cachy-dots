# rakazo

Self-hosts [Rakazo](https://github.com/elie222/rakazo) — the browser-automation
platform — in a dedicated Arch Linux VM on this host.

The VM runs in the user's libvirt session (`qemu:///session`), so a QEMU escape
lands in the user's account rather than root's, and is kept up by lingering
systemd user services. It sits alone on the bridge `rakazo0`
(10.41.41.0/30 — host .1, VM .2, static DHCP lease, nothing else):

- the VM reaches public addresses only: not the host, not the LAN, not NetBird,
  not other VMs (`rakazo-guard.service`, an nftables table the VM cannot be run
  without);
- bot computers inside the stack have restricted egress too (public
  addresses only);
- the web app is forwarded from the VM to loopback and the NetBird address
  (`wt0`) by `rakazo-web.socket` + `systemd-socket-proxyd`, host port 15173.

## Files

| File            | What it does |
| --------------- | ------------ |
| `common.sh`     | Shared constants (VM, bridge, ports, IPs) and message helpers; sourced by the other scripts. |
| `host-setup.sh` | One-time root setup: packages, the libvirt network and bridge, the qemu bridge-helper allowlist, `rakazo-guard.service` (nftables), matching ufw rules, and lingering. |
| `install.sh`    | As the user (never sudo): fetches the newest Rakazo release with both images on GHCR, creates the VM from the verified Arch cloud image with cloud-init and pinned SSH keys, installs the units, and provisions the guest over SSH. |
| `guest.sh`      | Runs inside the VM as root, sent over SSH: Docker, the bot-computer egress rules, and upstream's `install-images.sh` at the chosen release. |

## Usage

```sh
sudo opt/services/rakazo/host-setup.sh            # once, as root
opt/services/rakazo/install.sh                    # then, as the user
```

`install.sh` is idempotent and converges: a re-run upgrades packages in the
guest and moves to the newest release, keeping the VM, its disk and its secrets
(`.env`, including the `ENCRYPTION_KEY` — back it up). Useful options:

```sh
install.sh --close-signups        # once your account exists (--open-signups reopens)
install.sh --tag vX.Y.Z           # pin a release instead of the newest
install.sh --listen-ip IP         # bind address; default is wt0's (NetBird) address
install.sh --listen-ip 127.0.0.1  # loopback only
install.sh --port N               # host port (default 15173)
install.sh --memory MiB --vcpus N --disk SIZE   # for a new VM; the first two also
                                                # apply to an existing one on restart
install.sh --remove               # stop and remove the units and the VM, keep the disk
install.sh --remove --purge       # also delete the disk and the keys
sudo host-setup.sh --remove       # take the bridge, network and guard back out
```

Rakazo accepts one origin only: sign in at `http://<NetBird address>:15173`,
from this host too (loopback answers but fails the origin check). Re-run
`install.sh` after the NetBird address changes.
