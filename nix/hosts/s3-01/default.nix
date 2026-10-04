{ ... }:
{
  imports = [
    ../../modules/xcpng.nix
    ./disko.nix
    ./seaweedfs.nix
  ];

  networking.hostName = "s3-01";
  networking.firewall.allowedTCPPorts = [ 22 ];
  systemd.network.networks."10-lan".dhcpV4Config.ClientIdentifier = "mac";
  system.stateVersion = "26.05";

  nix.settings.auto-optimise-store = true;

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGsY6TN4o1NLfgPejOHzdtiQ2Is1MawOCfgYbJoQ/3WT s3-01-break-glass"
  ];

  gewis.sshUserCa.enable = true;

  gewis.netbird = {
    enable = true;
    dnsLabel = "s3";
  };

  sops = {
    age.keyFile = "/var/lib/sops-nix/key.txt";
    defaultSopsFile = ../../../secrets/s3-01.yaml;
  };
}
