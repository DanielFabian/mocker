{ ... }:

{
  imports = [ ../../modules/installer ];

  boot.initrd.availableKernelModules = [ "virtio_console" ];
  boot.initrd.kernelModules = [ "virtio_console" ];
  boot.kernelParams = [
    "console=tty0"
    "console=hvc0"
    "loglevel=7"
  ];

  mocker = {
    osDisk = "/dev/disk/by-path/pci-0000:00:06.0";
    dataDisk = "/dev/disk/by-path/pci-0000:00:07.0";
    partSep = "-part";
  };
}
