{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  sessionUser = config.gewis.servicePc.user;

  aurora =
    { name, deps }:
    {
      description = "Aurora ${name}";
      environment.LOG_LEVEL = "INFO";
      serviceConfig = {
        ExecStart = "${pkgs.python3.withPackages deps}/bin/python ${inputs."aurora-${name}"}/main.py";
        EnvironmentFile = config.sops.secrets."aurora-${name}".path;
        Restart = "always";
        RestartSec = 5;
      };
    };
in
{
  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  systemd.services.aurora-lights-proxy = lib.mkMerge [
    (aurora {
      name = "lights-proxy";
      deps = ps: [
        ps.python-dotenv
        ps.python-socketio
        ps.requests
        ps.stupidartnet
        ps.websocket-client
      ];
    })
    {
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig.DynamicUser = true;
    }
  ];

  systemd.user.services.aurora-audio-player = lib.mkMerge [
    (aurora {
      name = "audio-player";
      deps = ps: [
        ps.python-dotenv
        ps.python-socketio
        ps.python-vlc
        ps.requests
        ps.websocket-client
      ];
    })
    {
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = sessionUser;
    }
  ];

  sops.secrets = {
    aurora-lights-proxy = {
      mode = "0400";
      restartUnits = [ "aurora-lights-proxy.service" ];
    };

    aurora-audio-player = {
      owner = sessionUser;
      mode = "0400";
    };
  };
}
