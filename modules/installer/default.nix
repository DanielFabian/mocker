{ config, pkgs, lib, installedSystem, ... }:

let
  cfg = config.mocker;
in
{
  imports = [ ../appliance/options.nix ];

  config = {
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    console.useXkbConfig = true;
    services.xserver.xkb = {
      model = "pc105";
      layout = "gb";
      variant = "colemak_dh";
      options = "caps:escape";
    };

    networking.hostName = "mocker-installer";

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
    };
    users.users.root.openssh.authorizedKeys.keys = (import ../appliance/authorized-keys.nix).keys;

    # Bake the installed appliance closure into the ISO's Nix store.
    isoImage.storeContents = lib.mkAfter [ installedSystem ];

    systemd.services.mocker-auto-install = {
      description = "Install closure-baked Mocker appliance onto ${cfg.osDisk}";
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = cfg.osDisk;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
      path = with pkgs; [
        coreutils
        dosfstools
        e2fsprogs
        gnused
        nix
        nixos-install-tools
        parted
        systemd
        util-linux
      ];
      script = ''
        set -eux

        if blkid -L nixos >/dev/null 2>&1; then
          echo "mocker-installer: ${cfg.osDisk} already has a 'nixos' labelled fs; refusing reinstall."
          exit 0
        fi

        wipefs -a ${cfg.osDisk} || true
        parted -s ${cfg.osDisk} -- mklabel gpt
        parted -s ${cfg.osDisk} -- mkpart ESP fat32 1MiB 513MiB
        parted -s ${cfg.osDisk} -- set 1 esp on
        parted -s ${cfg.osDisk} -- mkpart primary ext4 513MiB 100%

        partprobe ${cfg.osDisk} || true
        udevadm settle --timeout=30

        ESP=${cfg.osDisk}${cfg.partSep}1
        ROOT=${cfg.osDisk}${cfg.partSep}2

        mkfs.fat -F 32 -n BOOT "$ESP"
        mkfs.ext4 -L nixos "$ROOT"

        udevadm settle --timeout=30

        mkdir -p /mnt
        mount "$ROOT" /mnt
        mkdir -p /mnt/boot
        mount "$ESP" /mnt/boot

        nixos-install \
          --system ${installedSystem} \
          --no-root-password \
          --no-channel-copy

        sync
        sleep 5
        systemctl reboot
      '';
    };

    services.getty.helpLine = lib.mkForce ''
      Mocker auto-installer running. Check `journalctl -u mocker-auto-install -f`.
    '';

    system.stateVersion = "25.11";
  };
}
