{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption mkEnableOption mkPackageOption types mkIf literalExpression mdDoc;
  cnf = config.deploy;

  toplevel_drv = builtins.unsafeDiscardOutputDependency config.system.build.toplevel.drvPath;
in {
  options.deploy = {
    enable = mkEnableOption (mdDoc "Enable deployment for this NixOS configuration.");
    default = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = mdDoc ''
        Controls inclusion of this configuration when runninig `nixdeploy` without
        any specific target.
      '';
    };

    hostName = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = mdDoc ''
        This hostname is used to identify if we are not doing local build.

        Local build skips SSH access steps and runs all commands locally instead.
      '';
    };

    ssh = {
      host = mkOption {
        type = types.str;
        default = config.networking.hostName;
        defaultText = literalExpression "config.networking.hostName";
        description = mdDoc ''
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
      description = mdDoc ''
        Command used to elevate access to root.

        Set it to empty string if you connect directly to root account.
      '';
    };

    remoteBuild = mkEnableOption (mdDoc "Build on destination machine instead of local");
    nativeBuild = mkOption {
      type = types.bool;
      default = config.deploy.remoteBuild;
      description = mdDoc "Build natively instead of cross compilation when applicable.";
    };
    noCopySubstitute = mkEnableOption (mdDoc ''
      Disable substitution on copy to destination (copy everything from local
      machine). This might be required if target machine doesn't have access to
      the Internet or even if it just slower than direct copy.
    '');
  };

  config = mkIf config.deploy.enable {
    system.extraSystemBuilderCmds = ''
      sucmd='${config.deploy.sucmd}' substituteAll ${./nixdeploy-system-script.sh} $out/bin/nixdeploy
      chmod +x $out/bin/nixdeploy
    '';
  };
}
