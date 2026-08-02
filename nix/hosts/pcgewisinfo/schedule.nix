_: {
  systemd.timers.daily-poweroff = {
    description = "Power off daily at 23:00";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 23:00:00";
      Persistent = false;
    };
  };

  systemd.services.daily-poweroff = {
    description = "Power off the machine";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/systemctl poweroff";
    };
  };
}
