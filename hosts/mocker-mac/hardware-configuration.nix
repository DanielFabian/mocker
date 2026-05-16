{ lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/headless.nix")
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [
    "virtio_blk"
    "virtio_pci"
    "virtio_net"
    "virtio_rng"
    "virtio_console"
  ];
  boot.initrd.kernelModules = [ "virtio_console" ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/ci" = {
    device = "/dev/disk/by-label/mocker-ci";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=15s"
    ];
  };

  services.timesyncd.enable = lib.mkDefault true;

  boot.kernelParams = [
    "console=tty0"
    "console=hvc0"
    "loglevel=7"
  ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
