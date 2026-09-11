{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; })
    cfg
    browserWmClass
    needsKiosk
    sessionUnit
    ;

  browserUrl =
    browser:
    if browser.url != null then
      lib.escapeShellArg browser.url
    else
      ''"$(cat ${browser.urlFile})"'';

  # `--new-instance` keeps Firefox from handing the URL to an already running
  # instance and exiting, which would put the unit in a restart loop.
  # Firefox resolves `--profile` with realpath, so the directory has to exist
  # before it starts.
  browserLauncher =
    name: browser:
    pkgs.writeShellScript "service-pc-browser-${name}" ''
      set -eu
      url=${browserUrl browser}
      ${lib.optionalString browser.waitForUrl ''
        deadline=$(( $(date +%s) + ${toString browser.waitTimeout} ))
        until ${lib.getExe pkgs.curl} -sSf --max-time 5 -o /dev/null "$url"; do
          if [ ${toString browser.waitTimeout} -gt 0 ] && [ "$(date +%s)" -ge "$deadline" ]; then
            echo "service-pc-browser-${name}: $url did not answer within ${toString browser.waitTimeout}s; starting anyway" >&2
            break
          fi
          sleep 2
        done
      ''}
      profile="$HOME/.mozilla/firefox/service-pc-${name}"
      mkdir -p "$profile"
      exec env MOZ_ENABLE_WAYLAND=1 ${lib.getExe config.programs.firefox.finalPackage} \
        --name ${lib.escapeShellArg (browserWmClass name)} \
        --new-instance \
        --profile "$profile" \
        "$url"
    '';
in
{
  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (name: browser: {
      assertion = (browser.url == null) != (browser.urlFile == null);
      message = ''
        gewis.servicePc.browsers.${name} needs exactly one of `url` or `urlFile`.
      '';
    }) cfg.browsers;

    programs.ydotool.enable = lib.mkIf needsKiosk true;

    users.users.${cfg.user}.extraGroups = lib.mkIf needsKiosk [
      config.programs.ydotool.group
    ];

    systemd.user.services = lib.mapAttrs' (
      name: browser:
      lib.nameValuePair "service-pc-browser-${name}" (sessionUnit {
        description = "${name} browser for the service-PC session";
        exec = "${browserLauncher name browser}";
        wmClass = browserWmClass name;
        fullscreen = browser.kiosk;
        restart = "always";
        inherit (browser) workspace monitor;
      })
    ) cfg.browsers;

    programs.firefox = lib.mkIf (cfg.browsers != { }) {
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
        "datareporting.policy.dataSubmissionPolicyBypassNotification" = true;
      };
    };
  };
}
