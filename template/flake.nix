{
  description = "NixOS configurations with NixDeploy";

  inputs.nixosdeploy = {
    url = "gitlab:cynerd/nixosdeploy";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    systems,
    nixpkgs,
    nixosdeploy,
    ...
  }: let
    inherit (nixpkgs.lib) genAttrs composeManyExtensions;
    forSystems = genAttrs (import systems);
    withPkgs = func: forSystems (system: func self.legacyPackages.${system});
  in {
    overlays = {
      pkgs = import ./pkgs;
      default = composeManyExtensions [
        # You can add here package overlays from other inputs.
        self.overlays.pkgs
      ];
      lib = composeManyExtensions [
        # You can add here library overlays from other inputs.
        (import ./lib)
      ];
    };

    nixosModules = import ./nixos/modules self;
    nixosConfigurations = import ./nixos/configurations self;

    packages = forSystems (system: {
      inherit (nixosdeploy.packages.${system}) default;
    });

    legacyPackages =
      forSystems (system:
        nixpkgs.legacyPackages.${system}.extend self.overlays.default);

    formatter = withPkgs (pkgs: pkgs.alejandra);
  };
}
