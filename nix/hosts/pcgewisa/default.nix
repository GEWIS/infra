{ config, ... }:
let
  sessionUser = config.gewis.servicePc.user;
  mesh = [ config.gewis.netbird.interface ];
in
{
  networking.hostName = "pcgewisa";
  system.stateVersion = "26.05";

  networking.networkmanager.enable = true;

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
      multiMonitor = true;

      browsers.left = {
        urlFile = config.sops.secrets.leftScreenURL.path;
        monitor = 1;
        kiosk = true;
      };

      browsers.right = {
        urlFile = config.sops.secrets.rightScreenURL.path;
        monitor = 2;
        kiosk = true;
      };

      remote = {
        enable = true;
        passwordFile = config.sops.secrets.rdpPassword.path;
        firewallInterfaces = mesh;
      };
    };

    netbird = {
      enable = true;
      client = "netbird";
      dnsLabel = "pcgewisa";
    };

    zabbixAgent = {
      enable = true;
      firewallInterfaces = mesh;
    };
  };

  sops = {
    age.keyFile = "/persist/var/lib/sops-nix/key.txt";
    defaultSopsFile = ../../../secrets/pcgewisa.yaml;
    secrets.leftScreenURL.owner = sessionUser;
    secrets.rightScreenURL.owner = sessionUser;
    secrets.rdpPassword.owner = sessionUser;
  };
}
