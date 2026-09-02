{ config, lib, ... }:
let
  cfg = config.gewis.persistence;
in
{
  options.gewis.persistence = {
    enable = lib.mkEnableOption "a persistent /persist directory on an otherwise tmpfs root";
    extraDirectories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    extraFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems."/".neededForBoot = true;
    fileSystems."/persist".neededForBoot = true;

    environment.persistence."/persist" = {
      hideMounts = true;
      directories = [
        "/var/lib/nixos"
        "/var/lib/systemd"
        "/var/log/journal"
      ]
      ++ cfg.extraDirectories;
      files = [ "/etc/machine-id" ] ++ cfg.extraFiles;
    };
  };
}
