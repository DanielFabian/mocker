{
  description = "Mocker — Docker-run-shaped workload execution inside a one-shot Apple-Silicon NixOS VM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      lib = nixpkgs.lib;
    in
    {
      nixosConfigurations = {
        mocker-mac = lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs self; };
          modules = [ ./hosts/mocker-mac ];
        };
      };

      # Closure-baked installer ISO. Unlike the devhost ISO, this does not
      # evaluate a flake or fetch GitHub inside the VM during install: the
      # installed appliance system closure is copied into the ISO store and
      # installer.nix runs nixos-install --system against that closure.
      packages.aarch64-linux.mocker-mac-iso =
        let
          installedSystem = self.nixosConfigurations.mocker-mac.config.system.build.toplevel;
        in
        (lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = {
            inherit inputs self installedSystem;
          };
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-base.nix"
            ./hosts/mocker-mac/installer.nix
          ];
        }).config.system.build.isoImage;

      packages.aarch64-darwin =
        let
          pkgs = import nixpkgs { system = "aarch64-darwin"; };
        in
        {
          mocker = pkgs.writeShellApplication {
            name = "mocker";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.gnugrep
              pkgs.gnused
              pkgs.gawk
              pkgs.jq
              pkgs.openssh
              pkgs.vfkit
              pkgs.gvproxy
            ];
            text = builtins.readFile ./mac/mocker.sh;
          };
        };

      apps.aarch64-darwin.mocker = {
        type = "app";
        program = "${self.packages.aarch64-darwin.mocker}/bin/mocker";
      };
    };
}