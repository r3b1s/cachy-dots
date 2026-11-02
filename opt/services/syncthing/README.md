# syncthing

Rootless [Syncthing](https://syncthing.net/) (`syncthing/syncthing:2`) as a Podman Quadlet (`syncthing.service` under `systemd --user`), restricted at the network layer so that sync traffic can only ever cross Tailscale (`tailscale0`) and the web GUI is only reachable on `127.0.0.1:8384`.

## Usage

```sh
opt/services/syncthing/install.sh                 # as your own user, never sudo
opt/services/syncthing/install.sh --reconfigure   # ask for the Tailscale IP again
opt/services/syncthing/install.sh -n              # dry run: print what it would do
```

On the first run, [install.sh](file:///home/t/Dotfiles/cachy-dots/opt/services/syncthing/install.sh) prompts for this host's `tailscale0` IPv4 address (pressing Enter accepts `tailscale0`'s current address), substitutes `@TAILSCALE_IP@` in [syncthing.container](file:///home/t/Dotfiles/cachy-dots/opt/services/syncthing/syncthing.container), writes `~/.config/containers/systemd/syncthing.container`, reloads `systemd --user`, and starts `syncthing.service`. Subsequent runs reuse the address already recorded in the installed unit unless `--reconfigure` is passed.

Because this is a `systemd --user` unit, it stops when you log out unless lingering is enabled (`loginctl enable-linger`).

## Architecture and Design Decisions

### 1. Tailscale-only confinement via `pasta`

Rather than running Syncthing on the host network (`Network=host`) and relying on application settings to avoid the LAN or public relays, the container is isolated in its own network namespace with `pasta`:

```ini
Network=pasta:-4,--outbound-if4,tailscale0,-a,@TAILSCALE_IP@/10,-g,100.64.0.1,--no-map-gw
PublishPort=127.0.0.1:8384:8384
PublishPort=@TAILSCALE_IP@:22000:22000/tcp
PublishPort=@TAILSCALE_IP@:22000:22000/udp
```

* **Outbound binding (`--outbound-if4,tailscale0`):** `pasta` is a user-space Layer-4 socket proxy. When Syncthing opens an outbound connection inside the container, `pasta` opens a corresponding unprivileged socket on the host bound directly to `tailscale0` (`SO_BINDTODEVICE`). The container cannot reach the LAN or the public internet.
* **IPv4 only (`-4`):** Disables IPv6 inside the container so traffic cannot bypass the IPv4-bound `tailscale0` interface over an IPv6 route.
* **Container-internal prefix and gateway (`-a,@TAILSCALE_IP@/10,-g,100.64.0.1`):** These settings exist **only inside the container's network namespace** and never touch the host's interfaces or routing tables. By default, `pasta` copies the IPv4 address, netmask, and `main`-table routes from the `--outbound-if4` interface. However, Tailscale assigns a `/32` address to `tailscale0` and places its `100.64.0.0/10` routes in policy routing table 52 rather than the `main` table. Left to its defaults, `pasta` would copy a `/32` with zero routes into the container, causing every outbound `connect()` inside the container to fail immediately with `ENETUNREACH` (`network is unreachable`). Giving `pasta` `-a @TAILSCALE_IP@/10` and `-g 100.64.0.1` populates the container's virtual `tap` interface with a route so packets enter the tap device; `pasta` then terminates them in user space and connects on the host via `tailscale0`, where the host's policy routing (table 52) handles delivery.
* **No host loopback mapping (`--no-map-gw`):** By default, `pasta` translates traffic sent to the container's default gateway IP (`100.64.0.1`) to `127.0.0.1` on the host. `--no-map-gw` disables that translation so the container cannot reach host loopback services.
* **Scoped port publishing (`PublishPort`):** Port `22000` (TCP and UDP/QUIC) is bound on the host strictly to `@TAILSCALE_IP@`, never `0.0.0.0`. The web GUI (`8384`) is bound strictly to `127.0.0.1`. Port `21027` (local broadcast discovery) is not published at all because LAN broadcasts cannot cross `pasta`.

### 2. Peer configuration in Syncthing

Because the container cannot reach public discovery servers, relays, or LAN broadcast discovery:

* **Static peer addresses are required:** In the Syncthing GUI (*Remote Devices -> Edit -> Advanced -> Addresses*), set each peer's address explicitly instead of `dynamic`:
  ```text
  tcp://<peer-tailscale-ip>:22000, quic://<peer-tailscale-ip>:22000
  ```
* **Leave Syncthing's own Listen Addresses at `default`:** Inside the container, Syncthing should listen on `default` (`tcp://0.0.0.0:22000, quic://0.0.0.0:22000`); `PublishPort=@TAILSCALE_IP@:22000:22000/...` already restricts the host listener to `tailscale0`.
* **Disable global discovery, local discovery, NAT traversal, and relaying** in *Actions -> Settings -> Connections* to avoid periodic connection warnings in the logs against unreachable public endpoints.

### 3. Boot ordering with `tailscaled`

A `systemd --user` service cannot order itself `After=` the system-level `tailscaled.service`. If `syncthing.service` starts before `tailscale0` has its IPv4 address, `pasta` fails to bind `@TAILSCALE_IP@:22000` and exits; `Restart=on-failure` with `RestartSec=30` retries until `tailscale0` is up.

### 4. Storage, UID mapping, and Path consistency

```ini
UserNS=keep-id
Volume=%h/.local/share/syncthing-container:/var/syncthing
Volume=%h/Sync:%h/Sync
Environment=HOME=%h
Environment=STNODEFAULTFOLDER=1
```

* **`UserNS=keep-id`:** Maps the invoking user's UID/GID to the same UID/GID inside the container and adds a matching `/etc/passwd` entry. The upstream image entrypoint detects a non-root UID and `exec`s `syncthing` directly without attempting `chown`, `setcap`, or `su-exec`, and synced files on the host stay owned by your user.
* **Separate state and data mounts:** Syncthing's configuration, keys, and index database live in `~/.local/share/syncthing-container` (mounted over the image's `/var/syncthing` `VOLUME` so Podman never creates an anonymous volume owned by a subordinate UID). Only `~/Sync` is exposed for synced folders.
* **`Environment=HOME=%h`:** The upstream image sets `HOME=/var/syncthing` and `STHOMEDIR=/var/syncthing/config`. Setting `HOME=%h` while leaving `STHOMEDIR` untouched keeps Syncthing's state in `/var/syncthing/config`, while making `~/Sync` in the GUI resolve to `/home/<user>/Sync` — matching the host path and the `%h/Sync:%h/Sync` bind mount.

### 5. Container hardening

```ini
ReadOnly=true
DropCapability=ALL
NoNewPrivileges=true
```

The container's root filesystem is mounted read-only, all Linux capabilities are dropped, and `no_new_privs` is set. Because the non-root entrypoint path needs no capabilities and all persistent writes go to the two bind mounts (`~/.local/share/syncthing-container` and `~/Sync`), Syncthing runs with minimal privileges.
