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
      description = mdDoc "If this deployment is included if running nixturris without any system selected.";
    };

    hostName = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = mdDoc "This hostname is used to identify if we are no doing local build.";
    };

    ssh = {
      host = mkOption {
        type = types.str;
        default = config.networking.hostName;
        defaultText = literalExpression "config.networking.hostName";
        description = mdDoc "SSH host deploy should happen to";
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
    noCopySubstityte = mkEnableOption (mdDoc "Disable substitution on copy destination (copy everything from local machine)");
  };

  config = mkIf config.deploy.enable {
    system.extraSystemBuilderCmds = ''
      sucmd='${config.deploy.sucmd}' substituteAll ${./nixdeploy-system-script.sh} $out/bin/nixdeploy
      chmod +x $out/bin/nixdeploy
    '';
  };
}
