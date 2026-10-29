# Executor, the MCP gateway, with Thunderbird ESR and its MCP add-on.
#
# Executor runs from upstream's self-host image with the host network. The
# add-on's shim listens on the guest's own address: Executor's import accepts a
# loopback URL but then cannot use it. Neither the firewall nor the ACL opens
# its port, so only this guest reaches it. Thunderbird runs in an i3 session
# that LightDM logs the user `tbird` into at boot (i3.conf), with Firefox ESR
# for the providers' sign-in pages; sign in to the accounts there with
# `incus console cs-executor --type=vga`. apply.sh writes Executor's origin (the
# edge's https://<NetBird address>:<port>) to /var/lib/cachy-stack/origin.env.
{ pkgs, lib, service, ... }:
let
  shimUrl = "http://${service.guest}:8766";
  # Upstream's release, with update_url removed: it names the author's own
  # server, from which Thunderbird would otherwise update a fully privileged
  # add-on. Bump the version and hash to upgrade, after reading the diff.
  addonId = "thunderbird-mcp@tkasperczyk.dev";
  addonVersion = "0.10.0";
  addon = pkgs.runCommand "thunderbird-mcp-${addonVersion}.xpi"
    {
      src = pkgs.fetchurl {
        url = "https://github.com/TKasperczyk/thunderbird-mcp/releases/download/v${addonVersion}/thunderbird-mcp-v${addonVersion}.xpi";
        sha256 = "638b7512d4f8b30d71b1547e10372ac537f046cc05d196a867e3871684c19f8c";
      };
      nativeBuildInputs = [ pkgs.jq pkgs.unzip pkgs.zip ];
    } ''
    mkdir x && cd x && unzip -q $src
    jq -e '.browser_specific_settings.gecko.id == "${addonId}"' manifest.json >/dev/null
    jq 'del(.browser_specific_settings.gecko.update_url)' manifest.json > m && mv m manifest.json
    zip -qrX $out .
  '';
  thunderbird = pkgs.thunderbird-esr;
  shim = pkgs.writers.writePython3Bin "tb-mcp-shim" { flakeIgnore = [ "E" "W" ]; }
    (builtins.readFile ./tb-mcp-shim.py);
in
{
  # ── Executor ────────────────────────────────────────────────────────────────
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.executor = {
    image = "ghcr.io/usefulsoftwareco/executor-selfhost:2.0.0-beta.31";
    environment = {
      DO_NOT_TRACK = "1";
      EXECUTOR_DISABLE_ANALYTICS = "1";
      # MCP servers on private addresses (the shim, and whatever service.toml's
      # egress allows); plain HTTP only for the shim.
      EXECUTOR_APPS_ALLOW_PRIVATE_FETCH = "true";
      EXECUTOR_URL_ALLOW_HTTP_ORIGINS = builtins.toJSON [ shimUrl ];
    };
    environmentFiles = [ "/var/lib/cachy-stack/origin.env" ];   # BETTER_AUTH_URL
    volumes = [ "/var/lib/executor:/app/data" ];
    extraOptions = [ "--network=host" ];
  };
  systemd.tmpfiles.rules = [ "d /var/lib/executor 0700 root root -" ];
  networking.firewall.allowedTCPPorts = [ service.edge.upstream ];

  # ── The desktop: i3, logged in as tbird at boot ─────────────────────────────
  users.users.tbird = { isNormalUser = true; description = "Thunderbird and its sign-ins"; };
  services.xserver = {
    enable = true;
    windowManager.i3 = {
      enable = true;
      configFile = ./i3.conf;
      extraPackages = with pkgs; [ alacritty i3status rofi ];
    };
    displayManager.lightdm.enable = true;
  };
  services.displayManager = {
    autoLogin = { enable = true; user = "tbird"; };
    defaultSession = "none+i3";
  };
  services.spice-vdagentd.enable = true;
  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  # The sign-in pages (Google, Microsoft) open here: Thunderbird hands them to
  # the default browser and takes the answer on a localhost listener.
  programs.firefox = {
    enable = true;
    package = pkgs.firefox-esr;
    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DontCheckDefaultBrowser = true;
      OverrideFirstRunPage = "";
      NoDefaultBookmarks = true;
    };
  };
  xdg.mime.defaultApplications = {
    "text/html" = "firefox-esr.desktop";
    "x-scheme-handler/http" = "firefox-esr.desktop";
    "x-scheme-handler/https" = "firefox-esr.desktop";
  };

  # ── Thunderbird ─────────────────────────────────────────────────────────────
  programs.thunderbird = {
    enable = true;
    package = thunderbird;
    policies = {
      ExtensionSettings.${addonId} = {
        installation_mode = "force_installed";
        install_url = "file://${addon}";
        updates_disabled = true;
      };
      ExtensionUpdate = false;
      DisableAppUpdate = true;
      DisableTelemetry = true;
    };
  };
  # Started by i3 (i3.conf), and back within seconds whenever it exits: the MCP
  # add-on lives in it. Never give it a primary password, which would hold the
  # accounts locked after every start.
  systemd.user.services.thunderbird = {
    description = "Thunderbird, kept running for its MCP add-on";
    unitConfig.ConditionUser = "tbird";
    # The system's PATH, not the minimal one NixOS gives units: GIO hides every
    # application whose program is not on PATH, and Thunderbird would then find
    # no browser for the sign-in pages.
    environment.PATH = lib.mkForce "/run/wrappers/bin:/etc/profiles/per-user/tbird/bin:/run/current-system/sw/bin";
    serviceConfig = {
      ExecStart = "${thunderbird}/bin/thunderbird";
      Restart = "always";
      RestartSec = 3;
    };
  };

  # ── Proton Mail Bridge ──────────────────────────────────────────────────────
  # Proton's IMAP/SMTP for Thunderbird on 127.0.0.1:1143 and :1025 (STARTTLS,
  # Bridge's own certificate), headless, as tbird. Its keychain is pass, with a
  # GPG key that has no passphrase: this guest's disk is the secret. Log in once
  # with `incus exec cs-executor -t -- proton-bridge-login` (needs a paid plan).
  systemd.services.proton-bridge = {
    description = "Proton Mail Bridge (headless)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.pass pkgs.gnupg ];
    unitConfig.ConditionPathExists = "/home/tbird/.password-store";   # until the first login
    serviceConfig = {
      User = "tbird";
      ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "proton-bridge-login";
      runtimeInputs = with pkgs; [ coreutils gnupg pass protonmail-bridge systemd util-linux ];
      text = ''
        # Stops the Bridge service, opens its CLI as tbird (`login`, then `info`
        # for the IMAP/SMTP password Thunderbird needs, then `exit`), and starts
        # the service again. The first run makes the GPG key and pass store.
        [ "$(id -u)" = 0 ] || { echo "run it as root: incus exec cs-executor -t -- proton-bridge-login" >&2; exit 1; }
        systemctl stop proton-bridge.service
        # shellcheck disable=SC2016 # $HOME is tbird's, expanded by the inner shell
        runuser -u tbird -- env HOME=/home/tbird sh -c '
          gpg --list-secret-keys proton-bridge@localhost >/dev/null 2>&1 ||
            gpg --batch --quiet --passphrase "" --quick-gen-key proton-bridge@localhost default default never
          [ -d "$HOME/.password-store" ] || pass init proton-bridge@localhost
          exec protonmail-bridge --cli'
        systemctl start proton-bridge.service
        systemctl --no-pager --lines=0 status proton-bridge.service || true
      '';
    })
  ];

  systemd.services.tb-mcp-shim = {
    description = "Thunderbird MCP add-on with its token, for Executor (${shimUrl})";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      User = "tbird";
      ExecStart = "${shim}/bin/tb-mcp-shim ${service.guest} 8766";
      Restart = "always";
      RestartSec = 2;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      CapabilityBoundingSet = "";
    };
  };
}
