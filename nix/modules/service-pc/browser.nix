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
    exec env MOZ_ENABLE_WAYLAND=1 ${lib.getExe pkgs.firefox} \
      ${lib.optionalString cfg.browser.kiosk "--kiosk"} "$url"
  '';

  firefoxPolicies = {
    policies = {
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      DisableProfileImport = true;
      DontCheckDefaultBrowser = true;
      DisableAppUpdate = true;
      NoDefaultBookmarks = true;
      Preferences = {
        # Start blank; the URL arrives on the command line.
        "browser.startup.page" = {
          Value = 0;
          Status = "locked";
        };
        "browser.sessionstore.resume_from_crash" = {
          Value = false;
          Status = "locked";
        };
        "browser.shell.checkDefaultBrowser" = {
          Value = false;
          Status = "locked";
        };
      };
    };
  };
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

    environment.etc = lib.mkIf cfg.browser.enable {
      "firefox/policies/policies.json".source = lib.mkDefault (
        (pkgs.formats.json { }).generate "service-pc-firefox-policies.json" firefoxPolicies
      );
    };

    environment.systemPackages = lib.optional cfg.browser.enable pkgs.firefox;
  };
}
