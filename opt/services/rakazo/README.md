# rakazo

A stack of self-hosted services under [Incus](https://linuxcontainers.org/incus/), one NixOS guest per
directory in `services/`, published on the host's NetBird address. It runs [Rakazo](https://github.com/elie222/rakazo)
and [Executor](https://github.com/UsefulSoftwareCo/executor) (an MCP gateway) with Thunderbird ESR. The design
and its traps are in [opt/services/AGENTS.md](../AGENTS.md#4-rakazo).

## Files

| File | What it does |
| --- | --- |
| `host-setup.sh` | The one root step, run once with sudo: installs Incus, the subordinate ID ranges, `incus.socket`, the `incus-admin` group, and the ufw block for the stack's bridges. |
| `apply.sh` | Everything else, as the user: renders and applies the Incus objects, keeps the CA, copies this directory into each guest and runs `nixos-rebuild switch`. |
| `render.py` | Reads `stack.toml` and `services/*/service.toml` and prints the Incus objects (a bridge, ACL and profile per service). |
| `stack.toml` | The registry: prefix, subnet, uplink interface, base image, private ranges and the published port block. |
| `services/<name>/service.toml` | One service: its address index, type, resources, edge upstream and egress. |
| `services/<name>/default.nix` | The guest's NixOS configuration (`flake.nix` builds one per directory). |
| `flake.nix`, `flake.lock` | The NixOS configurations, one per service. |
| `modules/common.nix` | What every guest shares: the Incus guest profile, networking and flakes. |
| `incus/preseed.yaml` | The initial Incus setup `apply.sh` uses when there is no storage pool yet. |
| `services/rakazo/rakazo-up.sh` | Brings Rakazo up as upstream deploys it: its pinned install script and Compose file, run by `rakazo.service`. |
| `services/executor/` | Executor's VM: Executor's self-host image, the Thunderbird i3 session (`i3.conf`) and the MCP shim (`tb-mcp-shim.py`). |

## Usage

```sh
sudo opt/services/rakazo/host-setup.sh   # once, as root
opt/services/rakazo/apply.sh             # then, as the user; re-run after any change
opt/services/rakazo/apply.sh --render    # print the Incus objects without changing anything
```

`apply.sh` takes `--only NAME`, `--no-rebuild`, and `--remove [--purge]`. Run `-h` for the full list. The
`incus-admin` group applies to new logins only: log out once, or use `newgrp incus-admin` in a terminal.

Never run `sudo incus console`: root cannot open a window on the user's display.

## Secrets

Runtime facts and secrets stay out of the flake. `apply.sh` writes `/var/lib/cachy-stack/{ca.crt,origin.env}` in
the guests. The CA lives in `~/.local/share/cachy-stack/ca`; back it up along with Rakazo's `ENCRYPTION_KEY`
in the guest's `/var/lib/rakazo/.env`.
