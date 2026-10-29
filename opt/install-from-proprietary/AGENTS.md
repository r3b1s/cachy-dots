# Installing Proprietary Software (`opt/install-from-proprietary/`)

This directory holds opt-in installers for closed-source applications that the vendor
ships only as a prebuilt Linux artefact (tarball, AppImage, `.deb`). There is no source to
build (that is `opt/install-from-source/`) and no package in the Cachy, Arch or chaotic-aur
repos (those go in `PINNED` in `install/packages.sh`). Nothing here runs from `install.sh`.

## Pattern and Layout

```text
opt/install-from-proprietary/
├── AGENTS.md                  # This guide
└── <app>/
    └── install.sh             # Download, install and removal script
```

## Script Conventions (`install.sh`)

Follow the conventions of `opt/install-from-source/AGENTS.md` (shebang, strict mode, `say`/`warn`/`run`,
`-n|--dry-run`, `-h|--help` printing the header comment, `--remove`, `/usr/local` layout, desktop entry), with
these differences for a vendor binary:

* **Find the download programmatically.** Read the current URL from the vendor's download page or API, with
  `--url <url>` as an override. Do not hard-code a version that goes stale.
* **https only** (`curl --proto '=https' --tlsv1.2`). Verify a checksum or signature when the vendor publishes one.
  When it does not, say so in the header: TLS is then the only authenticity check.
* **Unpack as the invoking user, install as root.** Download and extract into a `mktemp -d` under
  `${XDG_CACHE_HOME:-$HOME/.cache}` (removed by a `trap`), then copy into `/usr/local/lib/<app>` with
  `cp -a --no-preserve=ownership` and `chown -R root:root`. Nothing from the archive runs or is written as root,
  and the installed tree is not writable by the user (vendor self-updaters must not be able to replace it).
* **Link the launcher** to `/usr/local/bin/<app>`; `--remove` deletes it only while it still points into the
  install dir.
* **Idempotent.** Record the source URL in the install dir and do nothing when a re-run resolves to the same one
  (`--force` reinstalls).
* **No setuid.** Do not `chmod u+s` a vendor binary (Electron's `chrome-sandbox`): Arch and CachyOS allow
  unprivileged user namespaces.
* **`--remove` keeps user data** (`~/.config/<app>` and the like).
* **Dependencies** are the runtime libraries the vendor documents, installed with `pacman -S --needed` only when
  missing. No toolchains, and nothing from the AUR.

## Apps

| Directory | Installs |
| :--- | :--- |
| **`antigravity/`** | Google Antigravity desktop app (the "Antigravity App" download; the standalone Antigravity IDE is a separate archive, not installed). Scrapes the archive URL from `antigravity.google/download`, which publishes no checksum. |

## Testing Rules

As the root `AGENTS.md` says, **never run the installers on the machine you edit the repo on**. Live installs belong on a
test VM. `-n` (which still reads the download page, but downloads nothing), `bash -n` and `shellcheck` can and should be
run locally.
