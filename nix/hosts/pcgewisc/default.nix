{
  lib,
  pkgs,
  config,
  ...
}:
{
  imports = [ ./disko.nix ];

  networking.hostName = "pcgewisc";
  system.stateVersion = "26.05";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  networking.networkmanager.enable = true;

  users.users.cbc = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets.cbcPassword.path;
  };

  security.sudo.wheelNeedsPassword = false;

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "spotify" ];
  gewis = {
    comin.enable = true;

    persistence = {
      enable = true;
      extraDirectories = [ "/home/gewis" ];
    };

    servicePc = {
      enable = true;
      uid = 1000;
      workspaces = 2;
      touch = {
        enable = true;
      };

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

      remote = {
        enable = true;
        passwordFile = config.sops.secrets.rdpPassword.path;
        # Reachable over the mesh only. Named literally rather than read from
        # services.netbird, because gewis.netbird cannot be enabled until this
        # host has a sops file to keep its setup key in.
        firewallInterfaces = [ "nb-netbird" ];
      };
    };

    netbird = {
      enable = true;
      client = "netbird";
      dnsLabel = "pcgewisc";
    };
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
    defaultSopsFile = ../../../secrets/pcgewisc.yaml;
    #secrets.kioskUrl.owner = "gewis";
    secrets.cbcPassword.neededForUsers = true;
    secrets.rdpPassword.owner = "gewis";
    secrets.sudososUrl.owner = "gewis";
  };
}
