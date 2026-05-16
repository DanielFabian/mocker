{ config, pkgs, ... }:

let
  cfg = config.mocker;
in
{
  systemd.services.mocker-init-ci-disk = {
    description = "Initialize persistent /ci disk on first boot";
    wantedBy = [ "local-fs-pre.target" ];
    before = [ "local-fs-pre.target" ];
    unitConfig = {
      DefaultDependencies = false;
      ConditionPathExists = cfg.dataDisk;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [ util-linux e2fsprogs systemd ];
    script = ''
      set -eu
      if blkid ${cfg.dataDisk} >/dev/null 2>&1; then
        echo "mocker: ${cfg.dataDisk} already initialized, skipping mkfs"
        exit 0
      fi
      echo "mocker: formatting ${cfg.dataDisk} as ext4 (label=mocker-ci)"
      mkfs.ext4 -L mocker-ci -F ${cfg.dataDisk}
      udevadm settle --timeout=30
    '';
  };

  systemd.tmpfiles.rules = [
    "d /ci 0755 root root -"
    "d /ci/docker 0711 root root -"
    "d /ci/cargo 0777 root root -"
    "d /ci/rustup 0777 root root -"
    "d /ci/target 0777 root root -"
    "d /ci/sccache 0777 root root -"
    "d /ci/logs 0777 root root -"
    "d /ci/tmp 1777 root root -"
  ];
}
