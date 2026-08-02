{ ... }:
{
  imports = [
    ./boot.nix
    ./comin.nix
    ./disko.nix
    ./kiosk.nix
    ./networking.nix
    ./persistence.nix
    ./printers.nix
    ./schedule.nix
  ];

  networking.hostName = "pcgewisinfo";
  system.stateVersion = "26.05";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  nix.settings = {
    trusted-users = [ "cbc" ];
    substituters = [ "https://gewis.cachix.org" ];
    trusted-public-keys = [
      "gewis.cachix.org-1:bOcor+MaaLuUJN0Yj/IHCXsOQWm/RxSokm6BHGcbF5k="
    ];
  };

  gewis.netbird = {
    enable = true;
    client = "netbird";
    dnsLabel = "pcgewisinfo";
  };

  services.openssh = {
    openFirewall = false;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
    };
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  sops = {
    age.keyFile = "/persist/var/lib/sops-nix/key.txt";
    defaultSopsFile = ../../../secrets/pcgewisinfo.yaml;
    secrets.kioskUrl.owner = "gewis";
    secrets.cbcPassword.neededForUsers = true;
  };
}
