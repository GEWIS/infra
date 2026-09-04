{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; }) cfg sessionUnit;

  browserUrl =
    if cfg.browser.url != null then
      lib.escapeShellArg cfg.browser.url
    else
      ''"$(cat ${cfg.browser.urlFile})"'';

  browserLauncher = pkgs.writeShellScript "service-pc-browser" ''
    set -eu
    url=${browserUrl}
    ${lib.optionalString cfg.browser.waitForUrl ''
      deadline=$(( $(date +%s) + ${toString cfg.browser.waitTimeout} ))
      until ${lib.getExe pkgs.curl} -sSf --max-time 5 -o /dev/null "$url"; do
        if [ ${toString cfg.browser.waitTimeout} -gt 0 ] && [ "$(date +%s)" -ge "$deadline" ]; then
          echo "service-pc-browser: $url did not answer within ${toString cfg.browser.waitTimeout}s; starting anyway" >&2
          break
        fi
        sleep 2
      done
    ''}
    exec env MOZ_ENABLE_WAYLAND=1 ${lib.getExe config.programs.firefox.finalPackage} \
      ${lib.optionalString cfg.browser.kiosk "--kiosk"} "$url"
  '';
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.browser.enable -> ((cfg.browser.url == null) != (cfg.browser.urlFile == null));
        message = ''
          gewis.servicePc.browser needs exactly one of `url` or `urlFile`.
        '';
      }
    ];

    systemd.user.services = lib.mkIf cfg.browser.enable {
      service-pc-browser = sessionUnit {
        description = "Browser for the service-PC session";
        exec = "${browserLauncher}";
        wmClass = "firefox";
        inherit (cfg.browser) workspace monitor;
      };
    };

    programs.firefox = lib.mkIf cfg.browser.enable {
      enable = true;

      policies = {
        OverrideFirstRunPage = "";
        OverridePostUpdatePage = "";
        DisableProfileImport = true;
        DontCheckDefaultBrowser = true;
        NoDefaultBookmarks = true;
      };

      preferences = {
        "browser.startup.page" = 0;
        "browser.sessionstore.resume_from_crash" = false;
        "browser.shell.checkDefaultBrowser" = false;
      };
    };
  };
}
