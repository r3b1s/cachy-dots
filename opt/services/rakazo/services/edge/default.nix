# Caddy terminates TLS for every published port and proxies to the service's
# guest. apply.sh puts the leaf certificate in /var/lib/cachy-edge/tls (root
# only) and the NetBird address, which the certificate is for, in
# /var/lib/cachy-edge/env.
{ lib, pkgs, services, ... }:
let
  published = lib.filter (s: s.port != null) (lib.attrValues services);
  site = s: ''
    :${toString s.port} {
    	tls /run/caddy-tls/leaf.crt /run/caddy-tls/leaf.key
    	reverse_proxy ${s.guest}:${toString s.edge.upstream}
    }
  '';
in
{
  services.caddy = {
    enable = true;
    environmentFile = "/var/lib/cachy-edge/env";
    # Clients connect by IP, so they send no SNI.
    globalConfig = ''
      auto_https off
      default_sni {$EDGE_IP}
    '';
    extraConfig = lib.concatMapStrings site published;
  };
  # The key, readable by Caddy alone, for as long as it runs. Not LoadCredential:
  # Incus clears it for every service in a container (zzz-lxc-service.conf).
  systemd.services.caddy.serviceConfig = {
    RuntimeDirectory = "caddy-tls";
    RuntimeDirectoryMode = "0700";
    ExecStartPre = [ "+${pkgs.coreutils}/bin/install -o caddy -g caddy -m 0400 -t /run/caddy-tls /var/lib/cachy-edge/tls/leaf.crt /var/lib/cachy-edge/tls/leaf.key" ];
  };
  networking.firewall.allowedTCPPorts = map (s: s.port) published;
}
