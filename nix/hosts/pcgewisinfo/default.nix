{ config, ... }:
{
  imports = [
    ./boot.nix
    ./disko.nix
    ./fonts.nix
    ./networking.nix
    ./persistence.nix
    ./printers.nix
    ./schedule.nix
  ];

  networking.hostName = "pcgewisinfo";
  system.stateVersion = "26.05";

  users.users.cbc = {
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets.cbcPassword.path;
    extraGroups = [ "wheel" ];
  };

  security.sudo.wheelNeedsPassword = false;

  gewis.servicePc = {
    enable = true;
    uid = 1000;

    browser = {
      enable = true;
      urlFile = config.sops.secrets.kioskUrl.path;
      # No input devices to navigate away with, so kiosk mode costs nothing here.
      kiosk = true;
    };
  };

  # Mice are hidden via udev rather than disabled, to drop the cursor without a compositor-level hack.
  services.udev.extraRules = ''
    SUBSYSTEM=="input", ENV{ID_INPUT_MOUSE}=="1", ENV{LIBINPUT_IGNORE_DEVICE}="1"
  '';

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  nix.settings = {
    trusted-users = [ "cbc" ];
    substituters = [ "https://gewis.cachix.org" ];
    trusted-public-keys = [
      "gewis.cachix.org-1:bOcor+MaaLuUJN0Yj/IHCXsOQWm/RxSokm6BHGcbF5k="
    ];
  };

  gewis.comin.enable = true;

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
