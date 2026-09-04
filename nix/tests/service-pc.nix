{ pkgs, inputs }:
let
  servicePc = {
    imports = [
      inputs.comin.nixosModules.comin
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

    gewis.servicePc = {
      enable = true;
      uid = 1000;
      workspaces = 2;

      browser = {
        enable = true;
        url = "about:blank";
        waitForUrl = false;
        kiosk = true;
        workspace = 1;
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
  };

  testScript = ''
    session = (
      "XDG_RUNTIME_DIR=/run/user/1000 "
      "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
    )

    def check(machine):
      machine.wait_for_unit("display-manager.service")
      machine.wait_until_succeeds("pgrep -u gewis gnome-shell")
      machine.wait_for_unit("service-pc-keyring.service", "gewis")
      machine.wait_for_unit("service-pc-rdp-credentials.service", "gewis")
      machine.wait_for_unit("service-pc-browser.service", "gewis")
      machine.wait_until_succeeds("pgrep -u gewis firefox")

      status = machine.succeed(f"su gewis -c '{session}grdctl status --show-credentials'")
      assert "Username: gewis" in status, status
      assert "Password: hunter2" in status, status
      assert "Unit status: active" in status, status

      machine.wait_for_open_port(3389)

    with subtest("a fresh machine"):
      fresh.start()
      check(fresh)
      fresh.shutdown()

    with subtest("a machine carrying a keyring nobody has the password of"):
      stale.start()
      stale.wait_for_unit("forgotten-keyring.service")
      stale.succeed("test -s /home/gewis/.local/share/keyrings/login.keyring")
      check(stale)
  '';
}
