{ config, pkgs, lib, ... }:

{
  imports = [
    ./options.nix
    ./data-disk.nix
    ./docker.nix
    ./job-runner.nix
    ./wipe.nix
  ];

  networking.hostName = "mocker";
  networking.useDHCP = lib.mkDefault true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    trustedInterfaces = [ "docker0" ];
  };

  time.timeZone = "Europe/Zurich";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc.automatic = false;

  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    jq
    tmux
    vim
  ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      PrintMotd = true;
    };
  };

  users.mutableUsers = false;
  users.users.dany = {
    isNormalUser = true;
    description = "Daniel Fabian";
    home = "/home/dany";
    shell = pkgs.bash;
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = (import ./authorized-keys.nix).keys;
  };
  security.sudo.wheelNeedsPassword = false;

  systemd.tmpfiles.rules = [
    "d /home/dany 0755 dany users -"
  ];

  environment.etc."motd".text = ''
    === mocker ===
    One-shot Docker argv appliance.

    Normal use is host-driven:
      mocker run -- docker run ...

    Debug SSH is localhost-only via gvproxy from the Mac host.
  '';

  system.stateVersion = "25.11";
}
