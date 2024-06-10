{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption mkEnableOption types mkIf literalExpression;
in {
  options.deploy = {
    enable = mkEnableOption "Enable deployment for this NixOS configuration.";
    default = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = ''
        Controls inclusion of this configuration when runninig `nixdeploy` without
        any specific target.
      '';
    };

    ssh = {
      host = mkOption {
        type = types.str;
        default = config.networking.hostName;
        defaultText = literalExpression "config.networking.hostName";
        description = ''
          SSH host deploy should happen to.

          The default is the host name. That can be used by user to setup their
          own SSH configuration for their specific access. The example for host
          name `edge` would for example be:

          ```
          Host edge
            User john
            Hostname 10.4.0.139
            IdentityFile ~/.ssh/corporate
          ```
        '';
      };
    };
    sucmd = mkOption {
      type = types.str;
      default = "sudo";
      description = ''
        Command used to elevate access to root.

        Set it to empty string if you connect directly to root account.
      '';
    };

    remoteBuild = mkEnableOption "Build on destination machine instead of local";
    nativeBuild = mkOption {
      type = types.bool;
      default = config.deploy.remoteBuild;
      description = "Build natively instead of cross compilation when applicable.";
    };
    noCopySubstitute = mkEnableOption ''
      Disable substitution on copy to destination (copy everything from local
      machine). This might be required if target machine doesn't have access to
      the Internet or even if it just slower than direct copy.
    '';

    _dups = mkOption {
      type = types.anything;
      internal = true;
      visible = false;
      readOnly = true;
    };
  };

  config = {
    system.extraSystemBuilderCmds = mkIf config.deploy.enable ''
      sucmd='${config.deploy.sucmd}' \
        substituteAll ${./nixdeploy-system-script.sh} $out/bin/nixdeploy
      chmod +x $out/bin/nixdeploy
    '';

    deploy._dups = {
      inherit (config.networking) hostName;
    };
  };
}
