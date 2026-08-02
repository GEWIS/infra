{ ... }:
{
  imports = [
    ../../modules/xcpng.nix
    ./disko.nix
    ./garage.nix
  ];

  networking.hostName = "s3-01";
  networking.firewall.allowedTCPPorts = [ 22 ];
  system.stateVersion = "26.05";

  nix.settings.auto-optimise-store = true;

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHnm7ME9L/KuEGbSbzPJ4uVgsNl579UCCtXAIlWNYq7x luuk-blankenstijn@luuk-laptop"
  ];

  gewis.netbird.enable = true;

  sops = {
    age.keyFile = "/var/lib/sops-nix/key.txt";
    defaultSopsFile = ../../../secrets/s3-01.yaml;
  };
}
