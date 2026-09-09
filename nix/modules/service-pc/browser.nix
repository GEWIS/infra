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

  policiesJsonPath = "/etc/firefox/policies/policies.json";

  homepageScript = pkgs.writeShellScript "service-pc-browser-homepage" ''
    set -eu
    url=${browserUrl}
    tmp=$(${lib.getExe' pkgs.coreutils "mktemp"} ${policiesJsonPath}.XXXXXX)
    ${lib.getExe pkgs.jq} --arg url "$url" \
      '.policies.Homepage = {"URL": $url, "StartPage": "homepage"}' \
      ${policiesJsonPath} > "$tmp"
    mv -f "$tmp" ${policiesJsonPath}
  '';

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
    exec env MOZ_ENABLE_WAYLAND=1 ${lib.getExe config.programs.firefox.finalPackage} "$url"
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

    programs.ydotool.enable = lib.mkIf (cfg.browser.enable && cfg.browser.kiosk) true;

    users.users.${cfg.user}.extraGroups = lib.mkIf (cfg.browser.enable && cfg.browser.kiosk) [
      config.programs.ydotool.group
    ];

    systemd.user.services = lib.mkIf cfg.browser.enable {
      service-pc-browser = sessionUnit {
        description = "Browser for the service-PC session";
        exec = "${browserLauncher}";
        wmClass = "firefox";
        fullscreen = cfg.browser.kiosk;
        inherit (cfg.browser) workspace monitor;
      };
    };

    systemd.services.service-pc-browser-homepage = lib.mkIf cfg.browser.enable {
      description = "Home page for the service-PC browser";
      wantedBy = [ "multi-user.target" ];
      before = [ "display-manager.service" ];
      restartTriggers = [ config.environment.etc."firefox/policies/policies.json".source ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${homepageScript}";
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
        "browser.sessionstore.resume_from_crash" = false;
        "browser.shell.checkDefaultBrowser" = false;
        "datareporting.policy.dataSubmissionPolicyBypassNotification" = true;
      };
    };
  };
}
