{ config, lib, ... }:
let
  cfg = config.gewis.comin;
in
{
  options.gewis.comin.enable = lib.mkEnableOption "comin continuous deployment from GEWIS/infra";

  config = lib.mkIf cfg.enable {
    services.comin = {
      enable = true;
      remotes = [
        {
          name = "origin";
          url = "https://github.com/GEWIS/infra.git";
          branches.main.name = "main";
        }
      ];
    };

    # comin hardcodes this path itself: its clone of the repo and grpc.sock
    # live there, and its unit sets no StateDirectory.
    gewis.persistence.extraDirectories = [ "/var/lib/comin" ];
  };
}
