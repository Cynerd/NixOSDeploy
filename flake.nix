{
  description = "Simple tool to deploy NixOS system in various ways";

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }: let
    inherit (flake-utils.lib) eachDefaultSystem filterPackages;
  in
    {
      nixosModules.default = import ./nixos.nix;
      overlays.default = final: prev: {
        nixdeploy = final.callPackage ./pkg.nix {
          _srchash = "";
        };
      };
      s = self;
    }
    // (eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system}.extend self.overlays.default;
    in {
      packages.default = pkgs.nixdeploy;
      legacyPackages = pkgs;
      formatter = pkgs.alejandra;
    }));
}
