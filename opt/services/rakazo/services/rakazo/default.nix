# Rakazo, as upstream deploys it: install-images.sh and its Compose file at a
# pinned release, run by rakazo.service (rakazo-up.sh) as the user rakazo in
# /var/lib/rakazo. NixOS supplies Docker with upstream's daemon settings, and
# runs upstream's bot-computer egress script as a unit of its own: the script
# would install that unit under /etc/systemd/system, which NixOS keeps
# read-only.
#
# To upgrade: set `tag`, then each file's hash (nix store prefetch-file URL), and
# read upstream's changes to these files first.
{ pkgs, lib, service, ... }:
let
  tag = "v0.3.5";
  upstream = name: hash: pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/elie222/rakazo/${tag}/infra/compose/${name}";
    name = "rakazo-${tag}-${lib.removePrefix "." name}";
    inherit hash;
  };
  files = pkgs.linkFarm "rakazo-${tag}-files" {
    "install-images.sh" = upstream "install-images.sh" "sha256-E1qI1+wcBJDf+LdMucWQtiZqT7EYBsk0APXEgPU30mo=";
    "docker-compose.images.yml" = upstream "docker-compose.images.yml" "sha256-I61eGurHr6tY+/ZnD3fdjReGBFgSISKzFsupyHUZq/w=";
    ".env.images.example" = upstream ".env.images.example" "sha256-LoadNDXCQ2EkYR1ISfPXpF7SLk7pAlHHVDz7z9BtFOw=";
  };
  egress = upstream "restrict-computer-egress.sh" "sha256-+DpFUDq1PoXJ//VfPi1l+AIfMuePdn1uNiWzQgGBAPE=";
  dir = "/var/lib/rakazo";
  up = pkgs.writeShellApplication {
    name = "rakazo-up";
    runtimeInputs = with pkgs; [ bash coreutils curl docker gawk gnugrep gnused openssl ];
    text = builtins.readFile ./rakazo-up.sh;
  };
in
{
  # upstream's docker-daemon.json
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      live-restore = true;
      log-driver = "local";
      log-opts = { max-file = "3"; max-size = "10m"; };
      no-new-privileges = true;
      userland-proxy = false;
    };
  };

  users.users.rakazo = {
    isSystemUser = true;
    group = "rakazo";
    extraGroups = [ "docker" ];
    home = dir;
    createHome = true;
  };
  users.groups.rakazo = { };

  networking.firewall.allowedTCPPorts = [ service.edge.upstream ];

  # Bot computers reach public addresses only: not this guest, not the stack's
  # bridges, not the host's LAN. Re-applied whenever Docker restarts.
  systemd.services.rakazo-computer-egress = {
    description = "Rakazo bot computers: public egress only";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    partOf = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ bash coreutils gawk gnugrep iptables ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash ${egress} --apply";
    };
  };

  systemd.services.rakazo = {
    description = "Rakazo ${tag}";
    after = [ "docker.service" "rakazo-computer-egress.service" "network-online.target" ];
    requires = [ "docker.service" "rakazo-computer-egress.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      RAKAZO_TAG = tag;
      RAKAZO_FILES = "${files}";
      SIGNUPS = lib.boolToString service.signups;
      COMPUTER_DNS = "9.9.9.9,149.112.112.112";   # Quad9, and its secondary
      STACK_CA = "/var/lib/cachy-stack/ca.crt";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "rakazo";
      Group = "rakazo";
      WorkingDirectory = dir;
      EnvironmentFile = "/var/lib/cachy-stack/origin.env";
      ExecStart = "${up}/bin/rakazo-up";
      TimeoutStartSec = "45min";            # the first pull is several GB
    };
  };
}
