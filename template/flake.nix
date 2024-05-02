{
  description = "NixOS configurations with NixDeploy";

  inputs.nixosdeploy = {
    url = "gitlab:cynerd/nixosdeploy";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    flake-utils,
    nixpkgs,
    nixosdeploy,
    ...
  }: let
    inherit (flake-utils.lib) eachDefaultSystem;
    inherit (nixpkgs.lib) composeManyExtensions attrValues;
    revision = self.shortRev or self.dirtyShortRev or "unknown";
  in
    {
      overlays = {
        lib = _: prev: import ./lib prev;
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
                nixosdeploy.nixosModules.default
                # You can add here modules from other inputs.
              ]
              ++ (attrValues modules);
            config = {
              nixpkgs.overlays = [self.overlays.default];
              system.configurationRevision = revision;
            };
          };
        };

      nixosConfigurations = import ./nixos/configurations self;
      lib = import ./lib nixpkgs.lib;
    }
    // eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system}.extend self.overlays.default;
    in {
      packages.default = nixosdeploy.packages.${system}.default;
      legacyPackages = pkgs;
      formatter = pkgs.alejandra;
    });
}
