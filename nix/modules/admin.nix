{ config, lib, ... }:
let
  cfg = config.gewis.admin;
  hostKey = "/etc/ssh/ssh_host_ed25519_key";
in
{
  options.gewis.admin = {
    enable = lib.mkEnableOption "the administrator account with password login over ssh";

    user = lib.mkOption {
      type = lib.types.str;
      default = "cbc";
      description = "Name of the administrator account.";
    };

    passwordSecret = lib.mkOption {
      type = lib.types.str;
      default = "cbcPassword";
      description = "Name of the sops secret holding the account's hashed password.";
    };

    firewallInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''
        [ config.gewis.netbird.interface ]
      '';
      description = "Interfaces to open ssh on.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      hashedPasswordFile = config.sops.secrets.${cfg.passwordSecret}.path;
    };

    sops.secrets.${cfg.passwordSecret}.neededForUsers = true;

    security.sudo.wheelNeedsPassword = false;

    nix.settings.trusted-users = [ cfg.user ];

    services.openssh = {
      openFirewall = false;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = true;
        KbdInteractiveAuthentication = true;
      };
      hostKeys = [
        {
          path = hostKey;
          type = "ed25519";
        }
      ];
    };

    gewis.persistence.extraFiles = [
      hostKey
      "${hostKey}.pub"
    ];

    networking.firewall.interfaces = lib.genAttrs cfg.firewallInterfaces (_: {
      allowedTCPPorts = [ 22 ];
    });
  };
}
