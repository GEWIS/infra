{ lib, ... }:
{
  boot = {
    loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      device = "nodev";
    };
    loader.efi.canTouchEfiVariables = false;

    initrd.availableKernelModules = [
      "xen_blkfront"
      "xen_netfront"
      "ata_piix"
      "ahci"
      "sd_mod"
      "sr_mod"
    ];
    kernelParams = [
      "console=tty0"
      "console=ttyS0,115200"
    ];
  };
  networking = {
    useNetworkd = true;
    useDHCP = lib.mkForce false;
    nameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];
  };
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "en* eth*";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = true;
    };
    linkConfig.RequiredForOnline = "routable";
  };

  services.xe-guest-utilities.enable = true;
}
