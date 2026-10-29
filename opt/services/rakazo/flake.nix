{
  description = "cachy-dots service stack: one NixOS guest per services/<name>, under Incus";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      stack = fromTOML (builtins.readFile ./stack.toml);
      names = lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir ./services));
      # The same address plan as render.py: the guest is .2 on its index's /24,
      # and a published service's port is ports.first + index.
      service = name:
        let s = fromTOML (builtins.readFile ./services/${name}/service.toml);
        in s // {
          inherit name;
          guest = "${stack.subnet}.${toString s.index}.2";
          port = if s ? edge then stack.ports.first + s.index else null;
        };
      services = lib.genAttrs names service;
    in
    {
      nixosConfigurations = lib.genAttrs names (name: lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit stack services; service = services.${name}; };
        modules = [ ./modules/common.nix ./services/${name} ];
      });
    };
}
