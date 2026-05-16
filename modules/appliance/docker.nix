{ pkgs, ... }:

{
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      "data-root" = "/ci/docker";
    };
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  environment.systemPackages = with pkgs; [ docker-client ];
}
