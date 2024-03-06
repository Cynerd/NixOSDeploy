{
  lib,
  defaultModule,
}: let
  inherit (builtins) readDir;
  inherit (lib) filterAttrs hasSuffix mapAttrs' nameValuePair nixosSystem removeSuffix;
in
  mapAttrs' (
    fname: _: let
      name = removeSuffix ".nix" fname;
    in
      nameValuePair name (nixosSystem {
        modules = [
          (./. + ("/" + fname))
          {networking.hostName = name;}
          defaultModule
        ];
      })
  )
  (filterAttrs (
    n: v:
      v == "regular" && n != "default.nix" && hasSuffix ".nix" n
  ) (readDir ./.))
