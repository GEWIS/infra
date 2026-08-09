# Kiosk

`services.cage` runs Firefox fullscreen on tty1 as the unprivileged `gewis`
user. The launcher reads the target URL from the `kioskUrl` sops secret and
polls it with curl until it answers before starting the browser, so a slow or
briefly-down backend shows nothing rather than an error page. Firefox runs on
Wayland from a fresh throwaway profile each start.

The unit restarts on failure, up to 10 times in 60 seconds.

`autovt@tty1` is disabled. The `services.cage` module only sets
`Conflicts=getty@tty1.service` and `restartIfChanged = false`, so a
`nixos-rebuild switch` reactivates the getty on tty1, whose conflict stops the
running compositor — and cage is never restarted (`X-RestartIfChanged=false`,
and `Restart=on-failure` does not fire on a job-driven stop). Freeing the VT the
way the upstream `greetd` module does keeps cage on tty1 across a switch; the
session survives untouched until the next reboot.

Mice are hidden rather than disabled: a udev rule sets `LIBINPUT_IGNORE_DEVICE`
on every `ID_INPUT_MOUSE` device, which removes the pointer without a
compositor-level hack. Sleep, suspend, hibernate and hybrid-sleep targets are
disabled so the screen never blanks itself off.

`systemd.timers.daily-poweroff` powers the machine down at 23:00. Nothing turns
it back on — that is wake-on-schedule in firmware, or a human.
