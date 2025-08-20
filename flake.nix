{
  description = "Simple tool to deploy NixOS system in various ways";

  outputs = {
    self,
    nixpkgs,
    systems,
  }: let
    inherit (nixpkgs.lib) genAttrs;
    forSystems = genAttrs (import systems);
    withPkgs = func: forSystems (system: func self.legacyPackages.${system});

    _srchash = self.shortRev or self.dirtyShortRev or "unknown";
  in {
    nixosModules.default = import ./nixos.nix;

    overlays.default = final: _: {
      nixosdeploy = final.callPackage ./pkg.nix {inherit _srchash;};
    };

    templates.default = {
      path = ./template;
      description = "NixOS configurations deployed with NixDeploy";
    };

    packages = withPkgs (pkgs: {
      default = pkgs.nixosdeploy;
    });

    legacyPackages =
      forSystems (system:
        nixpkgs.legacyPackages.${system}.extend self.overlays.default);

    formatter = withPkgs (pkgs: pkgs.alejandra);
  };
}
