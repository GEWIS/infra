{ pkgs, inputs }:
let
  servicePc = {
    imports = [
      inputs.comin.nixosModules.comin
      inputs.disko.nixosModules.disko
      inputs.impermanence.nixosModules.impermanence
      inputs.sops-nix.nixosModules.sops
      ../modules
    ];

    virtualisation = {
      memorySize = 4096;
      cores = 2;
      diskSize = 8192;
    };

    environment.etc."service-pc-rdp-password" = {
      text = "hunter2";
      mode = "0444";
    };

    # Stands in for a host service such as geprint.
    systemd.services.restart-probe = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
    };

    gewis.servicePc = {
      enable = true;
      uid = 1000;
      workspaces = 2;
      # A host that stays on gets the nightly restart by default.
      shutdownAt = null;
      restart.services = [ "restart-probe" ];

      browsers = {
        first = {
          url = "about:blank";
          waitForUrl = false;
          kiosk = true;
          workspace = 1;
        };
        second = {
          url = "about:blank";
          waitForUrl = false;
          workspace = 2;
        };
      };

      apps.xterm = {
        package = pkgs.xterm;
        workspace = 2;
      };

      remote = {
        enable = true;
        passwordFile = "/etc/service-pc-rdp-password";
        openFirewall = true;
      };
    };
  };

  forgottenKeyring =
    { config, pkgs, ... }:
    {
      systemd.services.forgotten-keyring = {
        description = "A login keyring nobody has the password of";
        wantedBy = [ "multi-user.target" ];
        before = [ "display-manager.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = config.gewis.servicePc.user;
          RuntimeDirectory = "forgotten-keyring";
          Environment = "XDG_RUNTIME_DIR=/run/forgotten-keyring";
        };
        script = ''
          printf forgotten \
            | ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon \
                --unlock --components=pkcs11 --daemonize
        '';
      };
    };
  # The daemon is aborted the first time it comes up, after it has taken
  # org.freedesktop.secrets, which is what gnome-keyring does to itself now
  # and then when a client reads a collection property during its startup.
  crashingKeyring =
    { lib, pkgs, ... }:
    {
      systemd.user.services.service-pc-keyring.serviceConfig.ExecStartPost = lib.mkBefore [
        (pkgs.writeShellScript "abort-keyring-once" ''
          marker="$XDG_RUNTIME_DIR/keyring-aborted-once"
          [ -e "$marker" ] && exit 0
          touch "$marker"
          for _ in $(seq 1 30); do
            owner=$(${lib.getExe' pkgs.systemd "busctl"} --user call \
              org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus \
              GetConnectionUnixProcessID s org.freedesktop.secrets 2>/dev/null || true)
            [ "$owner" = "u $MAINPID" ] && break
            sleep 1
          done
          kill -ABRT "$MAINPID"
        '')
      ];
    };
in
pkgs.testers.runNixOSTest {
  name = "service-pc";

  node.specialArgs = { inherit inputs; };

  nodes = {
    fresh = servicePc;
    stale.imports = [
      servicePc
      forgottenKeyring
    ];
    crashing.imports = [
      servicePc
      crashingKeyring
    ];
  };

  testScript = ''
    session = (
      "XDG_RUNTIME_DIR=/run/user/1000 "
      "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
    )

    def check(machine):
      machine.wait_for_unit("display-manager.service")
      machine.wait_until_succeeds("pgrep -u gewis gnome-shell")
      machine.wait_for_unit("graphical-session.target", "gewis")
      machine.wait_for_unit("service-pc-keyring.service", "gewis")
      machine.wait_for_unit("service-pc-rdp-credentials.service", "gewis")
      for browser in ("first", "second"):
        machine.wait_for_unit(f"service-pc-browser-{browser}.service", "gewis")
        machine.wait_until_succeeds(f"pgrep -u gewis -f -- '--name firefox-{browser}'")
        machine.fail(f"journalctl -b _SYSTEMD_USER_UNIT=service-pc-browser-{browser}.service | grep -q service-pc-place:")
      machine.wait_for_unit("service-pc-app-xterm.service", "gewis")
      machine.wait_until_succeeds("pgrep -u gewis xterm")
      machine.fail("journalctl -b _SYSTEMD_USER_UNIT=service-pc-app-xterm.service | grep -q service-pc-place:")

      status = machine.succeed(f"su gewis -c '{session}grdctl status --show-credentials'")
      assert "Username: gewis" in status, status
      assert "Password: hunter2" in status, status
      assert "Unit status: active" in status, status

      machine.wait_for_open_port(3389)
      machine.fail("pgrep -u gewis -f gcr-prompter")

    def main_pids(machine):
      user = {
        unit: machine.succeed(
          f"su gewis -c '{session}systemctl --user show -p MainPID --value {unit}'"
        ).strip()
        for unit in (
          "service-pc-browser-first.service",
          "service-pc-browser-second.service",
          "service-pc-app-xterm.service",
        )
      }
      system = {"restart-probe.service": machine.succeed("systemctl show -p MainPID --value restart-probe.service").strip()}
      return user | system

    with subtest("a fresh machine"):
      fresh.start()
      check(fresh)

    with subtest("the nightly restart replaces every browser, app and listed service"):
      fresh.wait_for_unit("restart-probe.service")
      before = main_pids(fresh)
      fresh.succeed(f"su gewis -c '{session}systemctl --user start service-pc-restart.service'")
      fresh.succeed("systemctl start service-pc-restart.service")
      after = main_pids(fresh)
      for unit, pid in after.items():
        assert pid not in ("", "0", before[unit]), f"{unit}: {before[unit]} -> {pid}"
      for browser in ("first", "second"):
        fresh.wait_until_succeeds(f"pgrep -u gewis -f -- '--name firefox-{browser}'")
      fresh.shutdown()

    with subtest("a machine carrying a keyring nobody has the password of"):
      stale.start()
      stale.wait_for_unit("forgotten-keyring.service")
      stale.succeed("test -s /home/gewis/.local/share/keyrings/login.keyring")
      check(stale)
      stale.shutdown()

    with subtest("a keyring daemon that dies while the session starts"):
      crashing.start()
      check(crashing)
      restarts = crashing.succeed(
        f"su gewis -c '{session}systemctl --user show -p NRestarts --value service-pc-keyring.service'"
      )
      assert int(restarts) >= 1, restarts
  '';
}
