{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; }) cfg placed;

  # Only these windows depend on the layout; each restart places its window
  # again on the monitor it asked for.
  monitorUnits = map (p: "${p.unit}.service") (lib.filter (p: p.monitor != null) placed);

  resetScript = pkgs.writeShellScript "service-pc-display-reset" ''
    set -eu

    jq=${lib.getExe pkgs.jq}
    order_file="''${XDG_STATE_HOME:-$HOME/.local/state}/service-pc/monitor-order"

    state=$(${lib.getExe' pkgs.systemd "busctl"} --user --json=short call \
      org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig \
      org.gnome.Mutter.DisplayConfig GetCurrentState)

    joined=$(printf '%s' "$state" | "$jq" -r '
      .data[1] as $monitors | .data[2] as $logical
      | ($logical | length) == ($monitors | length)
        and all($logical[]; (.[5] | length) == 1)')

    if [ "$joined" = true ]; then
      mkdir -p "''${order_file%/*}"
      printf '%s' "$state" \
        | "$jq" -r '.data[2] | sort_by(.[0], .[1]) | map(.[5][0][0]) | join(" ")' >"$order_file"
      exit 0
    fi

    saved=$(cat "$order_file" 2>/dev/null || true)
    order=$(printf '%s' "$state" | "$jq" -r --arg saved "$saved" '
      [.data[1][][0][0]] as $connected
      | ($saved | split(" ") | map(select(IN($connected[])))) as $known
      | $known + ($connected - $known) | join(" ")')

    set --
    previous=""
    for connector in $order; do
      if [ -z "$previous" ]; then
        set -- "$@" --logical-monitor --primary --monitor "$connector"
      else
        set -- "$@" --logical-monitor --right-of "$previous" --monitor "$connector"
      fi
      previous=$connector
    done

    echo "service-pc-display-reset: displays were not joined; laying out $order left to right" >&2
    ${lib.getExe' pkgs.mutter "gdctl"} set "$@"
    ${lib.optionalString (monitorUnits != [ ]) ''
      ${lib.getExe' pkgs.systemd "systemctl"} --user restart --no-block ${lib.escapeShellArgs monitorUnits}
    ''}
  '';
in
{
  config = lib.mkIf (cfg.enable && cfg.resetDisplaysAt != null) {
    assertions = [
      {
        assertion = cfg.multiMonitor;
        message = ''
          gewis.servicePc.resetDisplaysAt needs gewis.servicePc.multiMonitor = true.
        '';
      }
    ];

    # ConditionUser scopes these to cfg.user; systemd user units otherwise
    # start for every logged-in user.
    systemd.user.timers.service-pc-display-reset = {
      description = "Join the service-PC displays at ${cfg.resetDisplaysAt}";
      wantedBy = [ "timers.target" ];
      unitConfig.ConditionUser = cfg.user;
      timerConfig.OnCalendar = cfg.resetDisplaysAt;
    };

    systemd.user.services.service-pc-display-reset = {
      description = "Join the service-PC displays side by side";
      after = [ "graphical-session.target" ];
      unitConfig.ConditionUser = cfg.user;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${resetScript}";
      };
    };
  };
}
