{
  lib,
  pkgs,
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
    hashedPasswordFile = "/run/secrets/cbcPassword";
  };

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "spotify" ];

  gewis.comin.enable = true;

  gewis.persistence = {
    enable = true;
    extraDirectories = [ "/home/gewis" ];
  };

  gewis.servicePc = {
    enable = true;
    uid = 1000;
    workspaces = 2;
    touch = {
      enable = true;
    };

    browser = {
      enable = true;
      url = "https://sudosos.gewis.nl/pos";
      workspace = 1;
      kiosk = true;
    };

    apps.spotify = {
      package = pkgs.spotify;
      workspace = 2;
    };

    remote = {
      enable = true;
      passwordFile = "/run/secrets/rdpPassword";
      # Reachable over the mesh only. Named literally rather than read from
      # services.netbird, because gewis.netbird cannot be enabled until this
      # host has a sops file to keep its setup key in.
      firewallInterfaces = [ "nb-netbird" ];
    };
  };
}
