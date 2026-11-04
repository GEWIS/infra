{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; }) cfg placed;

  systemctl = lib.getExe' pkgs.systemd "systemctl";

  # Every browser and extra app, plus whatever the host adds; a new browser is
  # restarted without anyone having to remember to list it.
  userUnits = map (p: "${p.unit}.service") placed ++ map (n: "${n}.service") cfg.restart.userServices;
  systemUnits = map (n: "${n}.service") cfg.restart.services;

  defined = option: units: name: {
    assertion = units ? ${name};
    message = ''
      gewis.servicePc.restart.${option} lists `${name}`, but no such unit is
      defined.
    '';
  };
in
{
  config = lib.mkIf (cfg.enable && cfg.restart.at != null) {
    assertions =
      map (defined "services" config.systemd.services) cfg.restart.services
      ++ map (defined "userServices" config.systemd.user.services) cfg.restart.userServices;

    systemd.timers.service-pc-restart = lib.mkIf (systemUnits != [ ]) {
      description = "Restart the service-PC system services at ${cfg.restart.at}";
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = cfg.restart.at;
    };

    systemd.services.service-pc-restart = lib.mkIf (systemUnits != [ ]) {
      description = "Restart the service-PC system services";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${systemctl} restart ${lib.escapeShellArgs systemUnits}";
      };
    };

    # ConditionUser scopes these to cfg.user; systemd user units otherwise
    # start for every logged-in user.
    systemd.user.timers.service-pc-restart = lib.mkIf (userUnits != [ ]) {
      description = "Restart the service-PC session's browsers, apps and services at ${cfg.restart.at}";
      wantedBy = [ "timers.target" ];
      unitConfig.ConditionUser = cfg.user;
      timerConfig.OnCalendar = cfg.restart.at;
    };

    systemd.user.services.service-pc-restart = lib.mkIf (userUnits != [ ]) {
      description = "Restart the service-PC session's browsers, apps and services";
      after = [ "graphical-session.target" ];
      unitConfig.ConditionUser = cfg.user;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${systemctl} --user restart ${lib.escapeShellArgs userUnits}";
      };
    };
  };
}
