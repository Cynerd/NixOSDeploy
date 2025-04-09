{
  description = "Simple tool to deploy NixOS system in various ways";

  outputs = {
    self,
    nixpkgs,
  }: let
    inherit (nixpkgs.lib) id genAttrs systems;
    withPkgs = func:
      genAttrs systems.flakeExposed (system:
        func (import nixpkgs {
          inherit system;
          overlays = [self.overlays.default];
        }));

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
    legacyPackages = withPkgs id;
    formatter = withPkgs (pkgs: pkgs.alejandra);
  };
}
