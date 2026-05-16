{ lib, ... }:

{
  options.mocker = {
    osDisk = lib.mkOption {
      type = lib.types.str;
      description = "Stable block device path for the disposable OS disk.";
    };

    dataDisk = lib.mkOption {
      type = lib.types.str;
      description = "Stable block device path for the persistent /ci data disk.";
    };

    partSep = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Separator between a disk path and partition number: empty for /dev/sda1,
        "-part" for /dev/disk/by-path/...-part1, "p" for nvme0n1p1.
      '';
    };
  };
}
