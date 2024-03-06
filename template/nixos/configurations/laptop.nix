{pkgs, lib, ...}: {
  system.stateVersion = "24.05";
  nixpkgs.hostPlatform.system = "x86_64-linux";

  deploy.enable = true;

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd.availableKernelModules = ["nvme" "xhci_pci" "usb_storage" "sd_mod"];
  };
  fileSystems = {
    "/" = {
      device = "/dev/sda2";
      fsType = "btrfs";
      options = ["compress=lzo" "subvol=@"];
    };
    "/boot" = {
      device = "/dev/sda1";
      fsType = "vfat";
    };
  };
  nixpkgs.config.allowUnfree = true;
  hardware.enableAllFirmware = true;
}
