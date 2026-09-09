{ config, lib, ... }:
let
  cfg = config.gewis.zabbixAgent;
in
{
  options.gewis.zabbixAgent = {
    enable = lib.mkEnableOption "the Zabbix agent";

    server = lib.mkOption {
      type = lib.types.str;
      default = "zabbix.gewis.nl";
      description = ''
        Comma-separated addresses, CIDR ranges or DNS names the agent answers
        passive checks from. It is matched against the source address the
        Zabbix server reaches this host from, which over the mesh is the
        server's mesh address and not its public one.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 10050;
      description = "TCP port the agent listens on.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open {option}`port` on every interface. Prefer
        {option}`firewallInterfaces` — an agent reachable from the whole LAN
        hands out host metrics to anyone who asks.
      '';
    };

    firewallInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''
        [ config.gewis.netbird.interface ]
      '';
      description = "Interfaces to open {option}`port` on.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (!cfg.openFirewall && cfg.firewallInterfaces == [ ]) ''
      gewis.zabbixAgent is enabled but nothing opens port ${toString cfg.port}:
      both zabbixAgent.openFirewall and zabbixAgent.firewallInterfaces are unset,
      so the firewall will drop every check.
    '';

    services.zabbixAgent = {
      enable = true;
      inherit (cfg) server openFirewall;
      listen.port = cfg.port;
    };

    networking.firewall.interfaces = lib.genAttrs cfg.firewallInterfaces (_: {
      allowedTCPPorts = [ cfg.port ];
    });
  };
}
