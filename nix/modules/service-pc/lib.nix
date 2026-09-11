{
  config,
  lib,
  pkgs,
}:
let
  cfg = config.gewis.servicePc;

  placeTimeoutSeconds = 60;
  fullscreenAttempts = 10;

  windowCalls = ''
    jq=${lib.getExe pkgs.jq}
    shell_call() {
      ${lib.getExe' pkgs.systemd "busctl"} --user --json=short call \
        org.gnome.Shell /org/gnome/Shell/Extensions/Windows \
        org.gnome.Shell.Extensions.Windows "$@"
    }
  '';

  findWindowScript = pkgs.writeShellScript "service-pc-find-window" ''
    set -eu

    tag="$1"
    class="$2"

    ${windowCalls}

    # Matched case-insensitively, against the instance name as well as the class.
    select_id='
      ($c | ascii_downcase) as $want
      | map(select(
          ((.wm_class // "") | ascii_downcase) == $want
          or ((.wm_class_instance // "") | ascii_downcase) == $want))
      | .[0].id // empty
    '

    id=""
    windows="[]"
    listed=no
    for _ in $(seq 1 ${toString placeTimeoutSeconds}); do
      if windows=$(shell_call List 2>/dev/null | "$jq" -r '.data[0]'); then
        listed=yes
        id=$(printf '%s' "$windows" | "$jq" -r --arg c "$class" "$select_id")
        [ -n "$id" ] && break
      fi
      sleep 1
    done

    if [ -z "$id" ]; then
      if [ "$listed" = no ]; then
        echo "$tag: org.gnome.Shell.Extensions.Windows never answered in ${toString placeTimeoutSeconds}s; is window-calls enabled?" >&2
      else
        seen=$(printf '%s' "$windows" \
          | "$jq" -r '[.[] | .wm_class] | unique | join(", ")' 2>/dev/null || echo "none")
        echo "$tag: no window with wm_class '$class' after ${toString placeTimeoutSeconds}s; saw: $seen" >&2
      fi
      exit 1
    fi

    printf '%s\n' "$id"
  '';

  placeScript = pkgs.writeShellScript "service-pc-place" ''
    set -eu

    class="$1"
    mode="$2"
    index="$3"

    ${windowCalls}

    # Exits 0 so a missing window doesn't take the whole unit down.
    id=$(${findWindowScript} service-pc-place "$class") || exit 0

    case "$mode" in
      workspace)
        shell_call MoveToWorkspace uu "$id" "$((index - 1))" >/dev/null
        ;;
      monitor)
        origin=$(${lib.getExe' pkgs.systemd "busctl"} --user --json=short call \
          org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig \
          org.gnome.Mutter.DisplayConfig GetCurrentState \
          | "$jq" -r --argjson i "$((index - 1))" \
              '.data[2] | if length > $i then "\(.[$i][0]) \(.[$i][1])" else empty end')
        if [ -z "$origin" ]; then
          echo "service-pc-place: monitor $index is not connected; leaving '$class' alone" >&2
          exit 0
        fi
        shell_call Move uii "$id" "''${origin% *}" "''${origin#* }" >/dev/null
        ;;
    esac

    # Always maximize: one app per workspace, so it should fill the screen.
    shell_call Maximize u "$id" >/dev/null
  '';

  fullscreenScript = pkgs.writeShellScript "service-pc-fullscreen" ''
    set -eu

    class="$1"

    ${windowCalls}

    # Exits 0 so a missing window doesn't take the whole unit down.
    id=$(${findWindowScript} service-pc-fullscreen "$class") || exit 0

    fullscreen_now() {
      shell_call Details u "$id" 2>/dev/null \
        | "$jq" -r '.data[0]' \
        | "$jq" -r '.fullscreen // false' 2>/dev/null || echo false
    }

    # Firefox keeps only a fullscreen state it entered itself, so it is driven
    # through its own F11 handler. F11 toggles, so the press is repeated only
    # while GNOME still reports the window as not fullscreen.
    attempt=0
    while [ "$attempt" -lt ${toString fullscreenAttempts} ]; do
      attempt=$((attempt + 1))

      # ydotool types into whatever the compositor considers focused.
      shell_call Activate u "$id" >/dev/null 2>&1 || true

      if ! err=$(env YDOTOOL_SOCKET=${config.environment.variables.YDOTOOL_SOCKET} \
        ${lib.getExe' pkgs.ydotool "ydotool"} key 87:1 87:0 2>&1 >/dev/null); then
        echo "service-pc-fullscreen: ydotool failed on attempt $attempt: $err" >&2
      fi

      sleep 1
      if [ "$(fullscreen_now)" = true ]; then
        exit 0
      fi
    done

    details=$(shell_call Details u "$id" 2>/dev/null | "$jq" -r '.data[0]' || true)

    # Exits 0 for the same reason the missing-window branch does.
    echo "service-pc-fullscreen: '$class' (id $id) is still not fullscreen after ${toString fullscreenAttempts} F11 presses" >&2
    printf '%s' "$details" \
      | "$jq" -c '{fullscreen, maximized, monitor, x, y, width, height, focus}' >&2 2>/dev/null || true
  '';

  # Shared by the browsers and the extra apps, so all are placed the same way.
  placement = {
    workspace = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      example = 2;
      description = ''
        Workspace to move the window to once it appears (starts at 1).
        Mutually exclusive with `monitor`.
      '';
    };

    monitor = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      example = 2;
      description = ''
        Monitor to move the window to once it appears (starts at 1), after
        which it is maximised there.
        Requires {option}`gewis.servicePc.multiMonitor`.
        Mutually exclusive with `workspace`.
      '';
    };
  };

  # Firefox derives its Wayland app-id from the program name `--name` sets, so
  # this is the wm_class the placement helper sees for that instance.
  browserWmClass = name: "firefox-${name}";

  browserModule = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "https://sudosos.gewis.nl/pos";
        description = ''
          URL to open. Mutually exclusive with `urlFile`; use that one if the
          URL contains an API key or other secret.
        '';
      };

      urlFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression "config.sops.secrets.kioskUrl.path";
        description = ''
          File read at launch to get the URL. Mutually exclusive with `url`.
        '';
      };

      kiosk = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Drop the browser into fullscreen once its window appears, by sending
          F11 via ydotool. The browser chrome stays reachable (address bar,
          keyboard shortcuts) behind the same F11 toggle a user would use. The
          press is repeated until GNOME reports the window as fullscreen.
        '';
      };

      waitForUrl = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Poll the URL before starting the browser.
        '';
      };

      waitTimeout = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 120;
        description = ''
          Seconds to keep polling before giving up and starting the browser
          anyway; 0 waits forever.
        '';
      };
    }
    // placement;
  };

  appModule = lib.types.submodule (
    { name, ... }:
    {
      options = {
        package = lib.mkOption {
          type = lib.types.package;
          example = lib.literalExpression "pkgs.spotify";
          description = "Package providing the application.";
        };

        exec = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Command used to start the application.
            Defaults to the package's `meta.mainProgram`.
          '';
        };

        wmClass = lib.mkOption {
          type = lib.types.str;
          default = name;
          example = "spotify";
          description = ''
            Window class the placement helper matches on. It has to equal the
            window's `wm_class` as GNOME reports it, which is usually but not
            always the binary name; check with `gdbus call --session -d
            org.gnome.Shell -o /org/gnome/Shell/Extensions/Windows -m
            org.gnome.Shell.Extensions.Windows.List` on a running session.
          '';
        };
      }
      // placement;
    }
  );

  # Everything the placement helper is asked to move, so the assertions can
  # check the browsers and the extra apps in one pass.
  placed =
    lib.mapAttrsToList (name: browser: {
      what = "gewis.servicePc.browsers.${name}";
      inherit (browser) workspace monitor;
    }) cfg.browsers
    ++ lib.mapAttrsToList (name: app: {
      what = "gewis.servicePc.apps.${name}";
      inherit (app) workspace monitor;
    }) cfg.apps;

  needsPlacement = lib.any (p: p.workspace != null || p.monitor != null) placed;

  needsKiosk = lib.any (browser: browser.kiosk) (lib.attrValues cfg.browsers);

  needsWindowCalls = needsPlacement || needsKiosk;

  # ConditionUser scopes this to cfg.user; systemd user units otherwise start for every logged-in user.
  sessionUnit =
    {
      description,
      exec,
      wmClass ? null,
      workspace ? null,
      monitor ? null,
      fullscreen ? false,
      restart ? "on-failure",
    }:
    {
      inherit description;
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      unitConfig.ConditionUser = cfg.user;
      serviceConfig = {
        ExecStart = exec;
        Restart = restart;
        RestartSec = 5;
        ExecStartPost =
          lib.optional (workspace != null) "${placeScript} ${
            lib.escapeShellArgs [
              wmClass
              "workspace"
              (toString workspace)
            ]
          }"
          ++ lib.optional (workspace == null && monitor != null) "${placeScript} ${
            lib.escapeShellArgs [
              wmClass
              "monitor"
              (toString monitor)
            ]
          }"
          ++ lib.optional fullscreen "${fullscreenScript} ${lib.escapeShellArg wmClass}";
      };
    };
in
{
  inherit
    cfg
    browserWmClass
    browserModule
    appModule
    placed
    needsPlacement
    needsKiosk
    needsWindowCalls
    sessionUnit
    ;
}
