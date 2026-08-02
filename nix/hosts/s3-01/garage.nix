{ config, pkgs, ... }:
{
  services.garage = {
    enable = true;
    package = pkgs.garage_2;

    settings = {
      replication_factor = 1;

      metadata_dir = "/var/lib/garage/meta";
      data_dir = "/var/lib/garage/data";
      metadata_auto_snapshot_interval = "6h";

      rpc_bind_addr = "[::1]:3901";
      rpc_public_addr = "[::1]:3901";
      rpc_secret_file = config.sops.secrets.garage-rpc-secret.path;

      s3_api = {
        api_bind_addr = "[::]:3900";
        s3_region = "garage";
      };

      admin = {
        api_bind_addr = "[::1]:3903";
        admin_token_file = config.sops.secrets.garage-admin-token.path;
      };
    };
  };

  systemd.services.garage.serviceConfig = {
    DynamicUser = false;
    User = "garage";
    Group = "garage";
  };

  users.users.garage = {
    isSystemUser = true;
    group = "garage";
  };
  users.groups.garage = { };

  sops.secrets = {
    garage-rpc-secret = {
      owner = "garage";
      mode = "0400";
      restartUnits = [ "garage.service" ];
    };

    garage-admin-token = {
      owner = "garage";
      mode = "0400";
      restartUnits = [ "garage.service" ];
    };
  };

  networking.firewall.allowedTCPPorts = [ 3900 ];
}
