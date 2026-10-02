{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.gewis.sshUserCa;
  caFile = "/var/lib/ssh-user-ca/ca.pub";
in
{
  options.gewis.sshUserCa = {
    enable = lib.mkEnableOption "logins with user certificates signed by the OpenBao SSH CA";

    url = lib.mkOption {
      type = lib.types.str;
      default = "https://openbao.cbc.gewis.nl:8443/v1/ssh/public_key";
      description = ''
        Unauthenticated endpoint the CA public key is fetched from. A failed or
        malformed fetch keeps the previous key, so certificates keep working
        while OpenBao is unreachable.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh.settings.TrustedUserCAKeys = caFile;

    systemd.services.ssh-user-ca = {
      description = "Fetch the OpenBao SSH user CA public key";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.diffutils
        pkgs.openssh
      ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "ssh-user-ca";
      };
      script = ''
        fetched=$(mktemp -p "$STATE_DIRECTORY")
        trap 'rm -f "$fetched"' EXIT
        curl --fail --silent --show-error --max-time 30 --output "$fetched" ${lib.escapeShellArg cfg.url}
        ssh-keygen -l -f "$fetched" > /dev/null
        if ! cmp -s "$fetched" ${caFile}; then
          chmod 0644 "$fetched"
          mv "$fetched" ${caFile}
        fi
      '';
    };

    systemd.timers.ssh-user-ca = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "15min";
      };
    };
  };
}
