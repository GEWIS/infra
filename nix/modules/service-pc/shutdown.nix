{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; }) cfg;
in
{
  config = lib.mkIf (cfg.enable && cfg.shutdownAt != null) {
    systemd.timers.service-pc-shutdown = {
      description = "Power off the service PC at ${cfg.shutdownAt}";
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = cfg.shutdownAt;
    };

    systemd.services.service-pc-shutdown = {
      description = "Power off the service PC";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe' pkgs.systemd "systemctl"} poweroff";
      };
    };
  };
}
