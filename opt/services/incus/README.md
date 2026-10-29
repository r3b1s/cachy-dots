# incus

The [Incus](https://linuxcontainers.org/incus/) daemon on the host (system containers and VMs), and nothing above
it: no storage pool, networks, profiles or instances. A stack built on Incus brings those itself (see
[rakazo](../rakazo/README.md)). The design notes are in [opt/services/AGENTS.md](../AGENTS.md#6-incus).

## Usage

```sh
opt/services/incus/install.sh            # as your own user: sudo is used for the root steps
opt/services/incus/install.sh --ui       # also the web UI
opt/services/incus/install.sh --remove   # take the setup out again
opt/services/incus/install.sh -n         # dry run: print what it would do
```

Re-running is safe: every step writes only when its target differs. The `incus-admin` group applies to new logins
only, so log out of the desktop session once, or use `newgrp incus-admin` in a terminal.

## What it sets up

| What | Where | Notes |
| --- | --- | --- |
| Packages | `incus`, `edk2-ovmf`; with `--ui` also `incus-ui` | Plain names, installed under a full `pacman -Syu` (never `-S` against a stale database). `edk2-ovmf` is the UEFI firmware VMs boot with. |
| Subordinate IDs | `/etc/subuid`, `/etc/subgid` | `root:1000000:1000000000` (`name:start:count`), added only when root has no entry. Unprivileged instances map their IDs into it. |
| Units | `incus.socket`, `incus.service` | Enabled and started. The service is enabled so instances with `boot.autostart` come back with the host. |
| Group | `incus-admin` | The invoking user is added. See below. |
| Firewall | `/etc/ufw/before.rules`, `/etc/ufw/before6.rules` | Only when ufw is installed: a managed block, `# >>> cachy-dots incus >>>`. See below. |
| Web UI | `incus webui` | Only with `--ui`. See below. |

### `incus-admin`, not `incus`

`incus-admin` is root-equivalent: a member can start a privileged instance that mounts the host's `/`, like
`libvirt` or `docker`. The other group, `incus`, only gives a restricted per-user project through
`incus-user.socket`, with no access to networks, storage or profiles, so it cannot manage a host's own Incus.
The script uses `incus-admin` only.

### Firewall

ufw drops an Incus bridge's DHCP and DNS requests to the host, and forwarding in and out of it, so instances on
the default bridge `incusbr0` would get no address and no network. The block, just before each `*filter` table's
`COMMIT`, accepts:

- DHCP (UDP 67 in `before.rules`, 547 in `before6.rules`) and DNS (UDP and TCP 53) from `incusbr0`, to the host;
- forwarding in and out of `incusbr0`.

That is narrower than `ufw allow in on incusbr0`, which opens every host port to the instances. Only that bridge
name is covered: a stack with bridges of its own adds its own block (rakazo's `host-setup.sh` does). The rest of
each file is never touched, and `--remove` takes the block out again.

### Web UI

`incus webui` starts a proxy on a loopback port that reaches the daemon over the local unix socket, and opens it in
your browser with a one-time token. No certificate is imported and nothing listens on the network. Letting other
machines in (`incus config set core.https_address ...` plus a trusted client certificate) is not set up.

## What it leaves alone

- **The daemon is not initialised.** Run `incus admin init` once, as your user: `--minimal` makes a `dir` pool
  called `default` and a NAT bridge `incusbr0`, and plain `incus admin init` asks instead. A stack that manages
  its own pool and bridges should skip `--minimal` and bring its own preseed: `--minimal` adds an `incusbr0` NIC to
  the default profile.
- **Restarts.** A restart of `incus.service` stops every running instance (`ExecStop=incusd shutdown`). The script
  restarts it only when a change needs one (new ID ranges, or `incus-ui` on a daemon that is already running) and
  only while no instance is running; otherwise it warns and leaves the restart to you.
- **`--remove`** takes the ufw blocks out, disables `incus.service` and `incus.socket` (which stops running
  instances) and removes `incus-ui`. The `incus` package, instances, storage, the ID ranges and the group stay.

## Checking it

```sh
systemctl is-active incus.socket incus.service
id -nG | tr ' ' '\n' | grep -x incus-admin   # after a new login
incus info                                    # "auth: trusted" means the group applies
```
