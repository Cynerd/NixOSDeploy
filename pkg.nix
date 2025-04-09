{
  stdenvNoCC,
  lib,
  makeWrapper,
  gawk,
  gnused,
  jq,
  util-linux,
  _srchash,
}:
stdenvNoCC.mkDerivation {
  pname = "nixosdeploy";
  version = "1.0.0-${_srchash}";
  nativeBuildInputs = [makeWrapper];
  dontUnpack = true;
  installPhase = ''
    mkdir -p $out/bin
    makeShellWrapper ${./nixosdeploy.sh} $out/bin/nixosdeploy \
    --prefix PATH : ${lib.makeBinPath [
      gawk
      gnused
      jq
      util-linux
    ]}
  '';
  meta = {
    description = "Script to deploy NixOS systems over SSH.";
    homepage = "https://gitlab.com/cynerd/nixosdeploy";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
