{ config, ... }:
let
  sessionUser = config.gewis.servicePc.user;
  mesh = [ config.gewis.netbird.interface ];
in
{
  imports = [
    ./boot.nix
    ./fonts.nix
    ./networking.nix
    ./printers.nix
  ];

  networking.hostName = "pcgewisinfo";
  system.stateVersion = "26.05";

  gewis = {
    admin = {
      enable = true;
      firewallInterfaces = [ "enp1s0" ] ++ mesh;
    };

    comin.enable = true;

    tmpfsRoot.enable = true;

    servicePc = {
      enable = true;
      uid = 1000;

      browser = {
        enable = true;
        urlFile = config.sops.secrets.kioskUrl.path;
        # No input devices to navigate away with, so kiosk mode costs nothing here.
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
      dnsLabel = "pcgewisinfo";
    };

    zabbixAgent = {
      enable = true;
      firewallInterfaces = mesh;
    };
  };

  # Mice are hidden via udev rather than disabled, to drop the cursor without a compositor-level hack.
  services.udev.extraRules = ''
    SUBSYSTEM=="input", ENV{ID_INPUT_MOUSE}=="1", ENV{LIBINPUT_IGNORE_DEVICE}="1"
  '';

  nix.settings = {
    substituters = [ "https://gewis.cachix.org" ];
    trusted-public-keys = [
      "gewis.cachix.org-1:bOcor+MaaLuUJN0Yj/IHCXsOQWm/RxSokm6BHGcbF5k="
    ];
  };

  sops = {
    age.keyFile = "/persist/var/lib/sops-nix/key.txt";
    defaultSopsFile = ../../../secrets/pcgewisinfo.yaml;
    secrets.kioskUrl.owner = sessionUser;
    secrets.rdpPassword.owner = sessionUser;
  };
}
