{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/appliance
  ];

  mocker = {
    # Empirical vfkit PCI assignment for the launcher's first two virtio-blk
    # devices, matching the proven sovereign-codespaces devhost-mac shape:
    # OS disk first -> 00:06.0, data disk second -> 00:07.0. Job/installer
    # ISOs are discovered by label, not by-path.
    osDisk = "/dev/disk/by-path/pci-0000:00:06.0";
    dataDisk = "/dev/disk/by-path/pci-0000:00:07.0";
    partSep = "-part";
  };

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 8 * 1024;
    }
  ];
}
