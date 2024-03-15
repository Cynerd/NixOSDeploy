self: let
  inherit (builtins) readDir;
  inherit (self.inputs) nixpkgs;
  inherit
    (nixpkgs.lib)
    filterAttrs
    hasSuffix
    mapAttrs'
    nameValuePair
    nixosSystem
    removeSuffix
    mapAttrs
    composeManyExtensions
    ;
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
            mapAttrs (n: v: v.nixosModules)
            (filterAttrs (n: v: v ? nixosModules) self.inputs);
          lib = nixpkgs.lib.extend (composeManyExtensions [
            self.overlays.lib
          ]);
        };
      })
  )
  (filterAttrs (
    n: v:
      v == "regular" && n != "default.nix" && hasSuffix ".nix" n
  ) (readDir ./.))
