{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; }) cfg;

  stateDir = "/var/lib/service-pc";
  rdpCert = "${stateDir}/rdp.crt";
  rdpKey = "${stateDir}/rdp.key";

  rdpCredentials =
    let
      username = if cfg.remote.username != null then cfg.remote.username else cfg.user;
      grdctl = lib.getExe' pkgs.gnome-remote-desktop "grdctl";
    in
    pkgs.writeShellScript "service-pc-rdp-credentials" ''
      set -eu
      grdctl() { ${lib.getExe' pkgs.coreutils "timeout"} 5 ${grdctl} "$@"; }
      for _ in $(seq 1 30); do
        grdctl rdp set-credentials ${lib.escapeShellArg username} \
          < ${cfg.remote.passwordFile} || true
        if grdctl status --show-credentials 2>/dev/null \
          | ${lib.getExe pkgs.gnugrep} -q "Username: ${username}"; then
          exit 0
        fi
        sleep 1
      done
      echo "service-pc-rdp-credentials: could not store the RDP password in the keyring" >&2
      exit 1
    '';
in
{
  config = lib.mkIf cfg.enable {
    gewis.persistence.extraDirectories = lib.mkIf cfg.remote.enable [ stateDir ];

    assertions = [
      {
        assertion = cfg.remote.enable -> cfg.remote.passwordFile != null;
        message = ''
          gewis.servicePc.remote.passwordFile is required when remote access is
          enabled.
        '';
      }
    ];

    warnings =
      lib.optional (cfg.remote.enable && !cfg.remote.openFirewall && cfg.remote.firewallInterfaces == [ ])
        ''
          gewis.servicePc.remote is enabled but nothing opens port ${toString cfg.remote.port}:
          both remote.openFirewall and remote.firewallInterfaces are unset, so the
          firewall will drop every connection to it.
        '';

    # Off unless remote access is wanted, even though GNOME defaults it on.
    services.gnome.gnome-remote-desktop.enable = cfg.remote.enable;

    services.gnome.gnome-keyring.enable = lib.mkIf cfg.remote.enable true;

    services.desktopManager.gnome = lib.mkIf cfg.remote.enable {
      extraGSettingsOverridePackages = [ pkgs.gnome-remote-desktop ];
      extraGSettingsOverrides = ''
        [org.gnome.desktop.remote-desktop.rdp]
        enable=true
        port=${toString cfg.remote.port}
        negotiate-port=false
        view-only=false
        tls-cert='${rdpCert}'
        tls-key='${rdpKey}'
        screen-share-mode='mirror-primary'
      '';
    };

    systemd.user.services = lib.mkIf cfg.remote.enable {
      gnome-remote-desktop = {
        overrideStrategy = "asDropin";
        wantedBy = [ "gnome-session.target" ];
      };

      service-pc-keyring-reset = {
        description = "Discard the login keyring of earlier service-PC sessions";
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        before = [ "service-pc-keyring.service" ];
        unitConfig.ConditionUser = cfg.user;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe' pkgs.coreutils "rm"} -rf %h/.local/share/keyrings";
        };
      };

      service-pc-keyring = {
        description = "Login keyring for service-PC remote access";
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        after = [
          "graphical-session.target"
          "service-pc-keyring-reset.service"
        ];
        before = [ "service-pc-rdp-credentials.service" ];
        unitConfig.ConditionUser = cfg.user;
        serviceConfig = {
          ExecStart = "/run/wrappers/bin/gnome-keyring-daemon --replace --unlock --foreground";
          StandardInput = "file:${cfg.remote.passwordFile}";
          Restart = "always";
          RestartSec = 2;
        };
      };

      # Written at runtime, not build time: the password lives in a keyring.
      service-pc-rdp-credentials = {
        description = "Credentials for service-PC remote access";
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        after = [
          "graphical-session.target"
          "service-pc-keyring.service"
        ];
        requires = [ "service-pc-keyring.service" ];
        before = [ "gnome-remote-desktop.service" ];
        unitConfig.ConditionUser = cfg.user;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = 120;
          ExecStart = "${rdpCredentials}";
        };
      };
    };

    # Generated once and kept
    systemd.services.service-pc-rdp-tls = lib.mkIf cfg.remote.enable {
      description = "Certificate for service-PC remote access";
      wantedBy = [ "multi-user.target" ];
      before = [ "display-manager.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "service-pc";
        StateDirectoryMode = "0755";
      };
      script = ''
        if [ ! -s ${rdpCert} ] || [ ! -s ${rdpKey} ]; then
          ${lib.getExe pkgs.openssl} req -x509 -newkey rsa:4096 -nodes -days 3650 \
            -subj "/CN=${config.networking.hostName}" \
            -keyout ${rdpKey} -out ${rdpCert}
        fi
        chown ${cfg.user} ${rdpCert} ${rdpKey}
        chmod 0644 ${rdpCert}
        chmod 0600 ${rdpKey}
      '';
    };

    networking.firewall = {
      allowedTCPPorts = lib.mkIf (cfg.remote.enable && cfg.remote.openFirewall) [ cfg.remote.port ];
      interfaces = lib.mkIf cfg.remote.enable (
        lib.genAttrs cfg.remote.firewallInterfaces (_: {
          allowedTCPPorts = [ cfg.remote.port ];
        })
      );
    };
  };
}
