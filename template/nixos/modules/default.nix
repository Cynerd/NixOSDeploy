self: let
  inherit (builtins) readDir;
  inherit (self.inputs.nixpkgs.lib) filterAttrs mapAttrs' nameValuePair attrValues;
  inherit (self.inputs.nixpkgs.lib) hasSuffix removeSuffix;

  modules =
    mapAttrs'
    (fname: _: nameValuePair (removeSuffix ".nix" fname) (./. + ("/" + fname)))
    (filterAttrs (
      n: v:
        v == "regular" && n != "default.nix" && hasSuffix ".nix" n
    ) (readDir ./.));
in
  modules
  // {
    default = {
      imports = with self.inputs;
        [
          nixosdeploy.nixosModules.default
          # You can add here modules from other inputs.
        ]
        ++ (attrValues modules);

      config = {
        nixpkgs.overlays = [self.overlays.default];
        system.configurationRevision = self.shortRev or self.dirtyShortRev or "unknown";
      };
    };
  }
