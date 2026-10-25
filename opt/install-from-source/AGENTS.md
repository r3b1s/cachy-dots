# Installing from Source (`opt/install-from-source/`)

This directory contains opt-in installer scripts for tools and applications built
directly from upstream source repositories or forges (GitHub, GitLab, Codeberg, etc.),
typically when upstream does not publish pre-built Linux packages or release binaries.

## Pattern and Layout

Each application has its own dedicated directory:

```text
opt/install-from-source/
├── AGENTS.md                  # This guide
└── <app>/
    ├── install.sh             # Build, install, and removal script
    └── mise.toml              # Scoped mise toolchain & build environment
```

### 1. Separation of Concerns: `mise` vs. `pacman`

Do not install language toolchains (Node, Rust, Go, Python) or specialized build CLIs
globally with `pacman` when they can be scoped to the build.

* **Pacman (System dependencies):**
  Only install OS-level shared libraries, desktop runtimes, C headers, and base system tools:
  * `mise` (installed via pacman if missing)
  * `base-devel`, `git`, `clang`, `nasm`, `perl`
  * System libraries: `webkit2gtk-4.1`, `gtk3`, `libayatana-appindicator`, `openssl`, `librsvg`, `xdotool`
* **Mise (`mise.toml`):**
  Manages language runtimes, compilers, and specialized CLI tools needed for compilation:
  * Runtime versions (e.g. `node = "24"`, `rust = "stable"`, `cmake = "latest"`, `tauri-cli = "latest"`)
  * Build-time environment variables in `[env]` (e.g. `NODE_OPTIONS`, `VITE_ENVIRONMENT_TYPE`, `SQLX_OFFLINE`)

This prevents polluting the host's system packages, prevents conflicts between system
runtimes (e.g. pacman `rust` vs `rustup`), and guarantees predictable, reproducible builds.

### 2. Scoped `mise.toml`

Every app directory must include a `mise.toml` declaring its tools and environment:

```toml
[tools]
node = "24"
rust = "stable"
tauri-cli = "latest"
cmake = "latest"

[env]
NODE_OPTIONS = "--max-old-space-size=8192"
VITE_ENVIRONMENT_TYPE = "production"
SQLX_OFFLINE = "true"
```

Use the latest supported versions that upstream documents.

### 3. Script Conventions (`install.sh`)

Every installer in this folder should follow these standards:

* **Shebang & strict mode:** `#!/usr/bin/env bash` and `set -euo pipefail`.
* **Path resolution:** Locate its own directory dynamically:
  ```bash
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ```
* **Standard CLI flags:**
  * `--tag <tag>`: Specify a release tag or branch (defaulting to the latest release tag via GitHub API or `main`).
  * `--build-dir <dir>`: Directory where the repository is cloned and built (default: `${XDG_CACHE_HOME:-$HOME/.cache}/<app>-build`).
  * `--clean`: Clean/wipe the build directory before or after the build.
  * `--remove`: Cleanly uninstall the application.
  * `-n|--dry-run`: Print commands without executing them.
  * `-h|--help`: Print usage instructions.
* **Mise invocation:**
  * Trust the local config: `mise trust "$SCRIPT_DIR/mise.toml"`
  * Install missing tools: `mise -C "$SCRIPT_DIR" install`
  * Run build steps through mise: `mise -C "$SCRIPT_DIR" exec -- <command>`
* **System integration:**
  * Binaries installed to `/usr/local/bin/<app>`.
  * Desktop entry installed to `/usr/local/share/applications/<app>.desktop` (with appropriate `StartupWMClass`).
  * Icons installed to `/usr/local/share/icons/hicolor/<size>/apps/<app>.png`.
  * Update caches: `update-desktop-database` and `gtk-update-icon-cache`.
* **Removal (`--remove`):**
  * Deletes the installed binary, `.desktop` file, and all associated icons from `/usr/local`.
  * Refreshes the desktop database and icon caches.
  * Optionally cleans the build directory when `--clean` is passed.

### 4. Testing Rules

As the root `AGENTS.md` says, **never run the build or installer scripts on the machine you edit the repo on**. Live builds belong on a test VM. Dry-run mode (`-n`) and syntax checks (`bash -n`) can and should be verified locally.
