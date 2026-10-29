# What every guest shares: the Incus guest profile, networking as the stock
# images:nixos config sets it up, flakes, and no sshd (incus exec is the way in).
{ lib, modulesPath, service, ... }:
{
  imports = [
    (if service.type == "virtual-machine"
     then "${modulesPath}/virtualisation/incus-virtual-machine.nix"
     else "${modulesPath}/virtualisation/lxc-container.nix")
  ];

  networking = {
    hostName = service.name;
    dhcpcd.enable = false;
    useDHCP = false;
    useHostResolvConf = false;
  };
  # The address is the static lease Incus gives the NIC (render.py's .2). Matched
  # by name: veths are ether links too, and networkd would take Docker's off
  # their bridges.
  systemd.network = {
    enable = true;
    networks."50-uplink" = {
      matchConfig.Name = "eth* en*";
      networkConfig.DHCP = "ipv4";
      linkConfig.RequiredForOnline = "routable";
    };
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Nix's build sandbox mounts a fresh /proc, which the kernel refuses in a
  # container while LXCFS has files mounted over /proc. Containers build only
  # small local derivations; everything else comes from the binary cache.
  nix.settings.sandbox = lib.mkIf (service.type == "container") false;
  services.openssh.enable = false;
  time.timeZone = "UTC";
  system.stateVersion = "26.05";
}
