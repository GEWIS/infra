{ config, lib, ... }:
let
  cfg = config.gewis.netbird;
  client = config.services.netbird.clients.${cfg.client};
in
{
  options.gewis.netbird = {
    enable = lib.mkEnableOption "the GEWIS NetBird mesh client";

    client = lib.mkOption {
      type = lib.types.str;
      default = "gewis";
      description = ''
        Attribute name of the NetBird client. It also names the systemd service,
        the wireguard interface (nb-<client>) and the state directory, so changing
        it on a joined host makes it register as a new peer.
      '';
    };

    dnsLabel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Extra DNS label the host is reachable under inside the mesh.";
    };

    setupKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "netbird-setupkey";
      description = "Name of the sops secret holding the NetBird setup key.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.netbird.clients.${cfg.client} = {
      autoStart = true;
      port = 51820;
      hardened = false;
      config.ServerSSHAllowed = true;

      environment = {
        NB_MANAGEMENT_URL = "https://nb.gewis.nl";
      }
      // lib.optionalAttrs (cfg.dnsLabel != null) {
        NB_EXTRA_DNS_LABELS = cfg.dnsLabel;
      };

      login = {
        enable = true;
        setupKeyFile = config.sops.secrets.${cfg.setupKeySecret}.path;
      };
    };

    services.resolved.enable = true;

    gewis.persistence.extraDirectories = [ client.dir.state ];

    sops.secrets.${cfg.setupKeySecret} = {
      mode = "0400";
      restartUnits = [ "${client.service.name}-login.service" ];
    };
  };
}
