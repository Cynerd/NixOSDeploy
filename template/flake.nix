{
  description = "NixOS configurations with NixDeploy";

  inputs.nixdeploy = {
    url = "gitlab:cynerd/nixdeploy";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    flake-utils,
    nixpkgs,
    nixdeploy,
    ...
  }: let
    inherit (flake-utils.lib) eachDefaultSystem;
    inherit (nixpkgs.lib) composeManyExtensions attrValues;
    revision = self.shortRev or self.dirtyShortRev or "unknown";
  in
    {
      overlays = {
        lib = final: prev: import ./lib prev;
        pkgs = import ./pkgs;
        default = composeManyExtensions [
          # You can add here overlays from other inputs.
          self.overlays.pkgs
        ];
      };

      nixosModules = let
        modules = import ./nixos/modules {inherit (nixpkgs) lib;};
      in
        modules
        // {
          default = {
            imports =
              [
                nixdeploy.nixosModules.default
                # You can add here modules from other inputs.
              ]
              ++ (attrValues modules);
            config = {
              nixpkgs.overlays = [self.overlays.default];
              system.configurationRevision = revision;
            };
          };
        };

      nixosConfigurations = import ./nixos/configurations {
        inherit (nixpkgs) lib;
        defaultModule = self.nixosModules.default;
      };
      lib = import ./lib nixpkgs.lib;
    }
    // eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system}.extend self.overlays.default;
    in {
      packages.default = nixdeploy.packages.${system}.default;
      legacyPackages = pkgs;
      formatter = pkgs.alejandra;
    });
}
