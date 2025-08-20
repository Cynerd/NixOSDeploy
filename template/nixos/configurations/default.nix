self: let
  inherit (builtins) readDir;
  inherit (self.inputs.nixpkgs) lib;
  inherit (lib) filterAttrs mapAttrs' mapAttrs nameValuePair;
  inherit (lib) hasSuffix removeSuffix nixosSystem;
in
  mapAttrs' (
    fname: _: let
      name = removeSuffix ".nix" fname;
    in
      nameValuePair name (nixosSystem {
        modules = [
          (./. + ("/" + fname))
          {networking.hostName = name;}
          self.nixosModules.default
        ];
        specialArgs = {
          inputModules =
            mapAttrs (_: v: v.nixosModules)
            (filterAttrs (_: v: v ? nixosModules) self.inputs);
          lib = lib.extend self.overlays.lib;
        };
      })
  )
  (filterAttrs (
    n: v:
      v == "regular" && n != "default.nix" && hasSuffix ".nix" n
  ) (readDir ./.))
