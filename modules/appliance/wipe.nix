{ config, pkgs, ... }:

let
  cfg = config.mocker;
in
{
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "mocker-wipe";
      runtimeInputs = with pkgs; [ coreutils util-linux systemd ];
      text = ''
        wipe_data=0
        do_reboot=1
        for arg in "$@"; do
          case "$arg" in
            --data) wipe_data=1 ;;
            --no-reboot) do_reboot=0 ;;
            -h|--help)
              echo "Usage: mocker-wipe [--data] [--no-reboot]"
              exit 0
              ;;
            *)
              echo "mocker-wipe: unknown argument: $arg" >&2
              exit 64
              ;;
          esac
        done

        if [[ $EUID -ne 0 ]]; then
          echo "mocker-wipe: must be run as root" >&2
          exit 1
        fi

        echo "mocker-wipe: OS disk = ${cfg.osDisk} (WILL be wiped)"
        if [[ $wipe_data -eq 1 ]]; then
          echo "mocker-wipe: /ci     = ${cfg.dataDisk} (WILL be wiped)"
        else
          echo "mocker-wipe: /ci     = ${cfg.dataDisk} (preserved)"
        fi
        read -r -p "Type 'wipe' to proceed: " confirm
        [[ "$confirm" == "wipe" ]] || exit 1

        wipefs --all --force ${cfg.osDisk} || true
        dd if=/dev/zero of=${cfg.osDisk} bs=1M count=1 conv=notrunc 2>/dev/null || true

        if [[ $wipe_data -eq 1 ]]; then
          wipefs --all --force ${cfg.dataDisk} || true
          dd if=/dev/zero of=${cfg.dataDisk} bs=1M count=1 conv=notrunc 2>/dev/null || true
        fi

        sync
        if [[ $do_reboot -eq 1 ]]; then
          systemctl reboot
        fi
      '';
    })
  ];
}
