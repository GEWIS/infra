{
  config,
  lib,
  pkgs,
  ...
}:
let
  sessionUser = config.gewis.servicePc.user;

  settings = (pkgs.formats.toml { }).generate "spotifyd.conf" {
    global = {
      device_name = "[Use me] GEWIS Speakers";
      device_type = "speaker";
      backend = "pulseaudio";
      disable_discovery = true;
      use_mpris = false;
      no_audio_cache = false;
      max_cache_size = 1000000000;
      volume_controller = "none";
      initial_volume = 0;
      volume_normalisation = true;
    };
  };
in
{
  systemd.user.services.spotifyd = {
    description = "spotifyd, a Spotify Connect speaker";
    wantedBy = [ "default.target" ];
    unitConfig = {
      ConditionUser = sessionUser;
      ConditionPathExists = "%C/spotifyd/oauth/credentials.json";
    };
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.spotifyd} --no-daemon --cache-path %C/spotifyd --config-path ${settings}";
      CacheDirectory = "spotifyd";
      Restart = "always";
      RestartSec = 5;
    };
  };

  environment.systemPackages = [ pkgs.spotifyd ];
}
