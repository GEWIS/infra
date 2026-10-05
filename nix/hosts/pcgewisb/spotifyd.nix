{
  config,
  lib,
  pkgs,
  ...
}:
let
  sessionUser = config.gewis.servicePc.user;
  zeroconfPort = 5354;

  settings = (pkgs.formats.toml { }).generate "spotifyd.conf" {
    global = {
      device_name = "GEWIS Bar";
      device_type = "speaker";
      backend = "pulseaudio";
      bitrate = 320;
      zeroconf_port = zeroconfPort;
    };
  };
in
{
  systemd.user.services.spotifyd = {
    description = "spotifyd, a Spotify Connect speaker";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = sessionUser;
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.spotifyd} --no-daemon --cache-path %C/spotifyd --config-path ${settings}";
      CacheDirectory = "spotifyd";
      Restart = "always";
      RestartSec = 5;
    };
  };

  environment.systemPackages = [ pkgs.spotifyd ];

  networking.firewall.interfaces.enp0s31f6.allowedTCPPorts = [ zeroconfPort ];
}
