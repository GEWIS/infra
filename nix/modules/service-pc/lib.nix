{
  config,
  lib,
  pkgs,
}:
let
  cfg = config.gewis.servicePc;

  placeTimeoutSeconds = 60;

  placeScript = pkgs.writeShellScript "service-pc-place" ''
    set -eu

    class="$1"
    mode="$2"
    index="$3"

    jq=${lib.getExe pkgs.jq}
    shell_call() {
      ${lib.getExe' pkgs.systemd "busctl"} --user --json=short call \
        org.gnome.Shell /org/gnome/Shell/Extensions/Windows \
        org.gnome.Shell.Extensions.Windows "$@"
    }

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
    for _ in $(seq 1 ${toString placeTimeoutSeconds}); do
      if windows=$(shell_call List 2>/dev/null | "$jq" -r '.data[0]'); then
        id=$(printf '%s' "$windows" | "$jq" -r --arg c "$class" "$select_id")
        [ -n "$id" ] && break
      fi
      sleep 1
    done

    # Exits 0 so a missing window doesn't take the whole unit down.
    if [ -z "$id" ]; then
      seen=$(printf '%s' "$windows" \
        | "$jq" -r '[.[] | .wm_class] | unique | join(", ")' 2>/dev/null || echo "none")
      echo "service-pc-place: no window with wm_class '$class' after ${toString placeTimeoutSeconds}s; saw: $seen" >&2
      exit 0
    fi

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

  # Shared by the browser and the extra apps, so both are placed the same way.
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
  # check the browser and the extra apps in one pass.
  placed =
    lib.optional cfg.browser.enable {
      what = "gewis.servicePc.browser";
      inherit (cfg.browser) workspace monitor;
    }
    ++ lib.mapAttrsToList (name: app: {
      what = "gewis.servicePc.apps.${name}";
      inherit (app) workspace monitor;
    }) cfg.apps;

  needsPlacement = lib.any (p: p.workspace != null || p.monitor != null) placed;

  # ConditionUser scopes this to cfg.user; systemd user units otherwise start for every logged-in user.
  sessionUnit =
    {
      description,
      exec,
      wmClass,
      workspace,
      monitor,
    }:
    {
      inherit description;
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      unitConfig.ConditionUser = cfg.user;
      serviceConfig = {
        ExecStart = exec;
        Restart = "on-failure";
        RestartSec = 5;
        ExecStartPost =
          if workspace != null then
            "${placeScript} ${
              lib.escapeShellArgs [
                wmClass
                "workspace"
                (toString workspace)
              ]
            }"
          else if monitor != null then
            "${placeScript} ${
              lib.escapeShellArgs [
                wmClass
                "monitor"
                (toString monitor)
              ]
            }"
          else
            [ ];
      };
    };
in
{
  inherit
    cfg
    placement
    appModule
    placed
    needsPlacement
    sessionUnit
    ;
}
