{
  stdenvNoCC,
  lib,
  makeWrapper,
  _srchash,
  gawk,
  gnused,
  jq,
}: let
  inherit (lib) licenses platforms makeBinPath;

  dependencies = [gawk gnused jq];
in
  stdenvNoCC.mkDerivation {
    pname = "nixdeploy";
    version = "1.0.0-${_srchash}";
    nativeBuildInputs = [makeWrapper];
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      makeShellWrapper ${./nixdeploy.sh} $out/bin/nixdeploy \
        --prefix PATH : ${makeBinPath dependencies}
    '';
    meta = {
      description = "Script to deploy NixOS systems over SSH.";
      homepage = "https://gitlab.com/cynerd/nixdeploy";
      license = licenses.gpl3Plus;
      platforms = platforms.linux;
    };
  }
