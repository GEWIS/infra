{ config,
  lib,
  pkgs,
  ... }:
let
  sessionUser = config.gewis.servicePc.user;
  mesh = [ config.gewis.netbird.interface ];
in
{
  networking.hostName = "pcgewisc";
  system.stateVersion = "26.05";

  networking.networkmanager.enable = true;

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "spotify" ];

  gewis = {
    admin = {
      enable = true;
      firewallInterfaces = mesh;
    };

    comin.enable = true;

    tmpfsRoot.enable = true;
    persistence.extraDirectories = [ "/home/${sessionUser}" ];

    servicePc = {
      enable = true;
      uid = 1000;
      workspaces = 2;
      justPerfection = true;
      touch.enable = true;

      browser = {
        enable = true;
        urlFile = config.sops.secrets.sudososUrl.path;
        workspace = 1;
        kiosk = true;
      };

      apps.spotify = {
        package = pkgs.spotify;
        workspace = 2;
      };

      nfcReader.enable = true;

      remote = {
        enable = true;
        passwordFile = config.sops.secrets.rdpPassword.path;
        firewallInterfaces = mesh;
      };
    };

    netbird = {
      enable = true;
      client = "netbird";
      dnsLabel = "pcgewisc";
    };

    zabbixAgent = {
      enable = true;
      firewallInterfaces = mesh;
    };
  };

  sops = {
    age.keyFile = "/persist/var/lib/sops-nix/key.txt";
    defaultSopsFile = ../../../secrets/pcgewisc.yaml;
    secrets.rdpPassword.owner = sessionUser;
    secrets.sudososUrl.owner = sessionUser;
  };
}
