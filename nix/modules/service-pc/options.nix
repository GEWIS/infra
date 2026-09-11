{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; })
    cfg
    browserModule
    appModule
    ;
in
{
  options.gewis.servicePc = {
    enable = lib.mkEnableOption "the GEWIS service-PC desktop session";

    user = lib.mkOption {
      type = lib.types.str;
      default = "gewis";
      description = ''
        Unprivileged user the graphical session, the browsers, the extra apps
        and the remote-access daemon all run as. The module creates it.
      '';
    };

    uid = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 1000;
      description = ''
        Fixed uid for {option}`user`, also used as the gid of its primary
        group. Pin it on hosts that keep state across reinstalls so file
        ownership survives.
      '';
    };

    workspaces = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      example = 2;
      description = ''
        Number of static workspaces.
      '';
    };

    multiMonitor = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        This host has more than one monitor connected.
      '';
    };

    justPerfection = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Load the Just Perfection GNOME extension.
      '';
    };

    shutdownAt = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "23:00";
      example = "*-*-* 22:30:00";
      description = ''
        Time the host powers itself off every day, as a systemd calendar
        expression. `null` keeps it running.
      '';
    };

    touch = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          This host is a touchscreen with no keyboard or mouse. Enables GNOME's
          on-screen keyboard and opens it whenever a text field gets focus.
        '';
      };

      vendorId = lib.mkOption {
        type = lib.types.str;
        default = "0eef";
        description = ''
          USB vendor ID of the touch panel, as reported by `lsusb`. The panel
          is reclassified from tablet to touchscreen for libinput.
        '';
      };

      productId = lib.mkOption {
        type = lib.types.str;
        default = "0001";
        description = "USB product ID of the touch panel, as reported by `lsusb`.";
      };
    };

    browsers = lib.mkOption {
      type = lib.types.attrsOf browserModule;
      default = { };
      example = lib.literalExpression ''
        {
          pos = {
            url = "https://sudosos.gewis.nl/pos";
            monitor = 1;
            kiosk = true;
          };
          dashboard = {
            url = "https://heeftjarmoautomatagehaald.nl";
            monitor = 2;
          };
        }
      '';
      description = ''
        Firefox windows to start with the session, keyed by name. Each runs as
        its own instance from its own profile, so several can be open at once
        and placed independently.
      '';
    };

    apps = lib.mkOption {
      type = lib.types.attrsOf appModule;
      default = { };
      example = lib.literalExpression ''
        {
          spotify = {
            package = pkgs.spotify;
            workspace = 2;
          };
        }
      '';
      description = ''
        Extra applications to start with the session, keyed by name.
      '';
    };

    nfcReader = {
      enable = lib.mkEnableOption ''
        a background NFC reader that types the scanned tag's ID as
        `nfc<hex-id>` followed by Enter, into whatever window has focus
      '';

      vendorId = lib.mkOption {
        type = lib.types.str;
        default = "072f";
        example = "072f";
        description = ''
          USB vendor ID of the NFC reader, as reported by `lsusb` (the first
          half of the `id` column).
        '';
      };

      productId = lib.mkOption {
        type = lib.types.str;
        default = "2200";
        example = "2200";
        description = ''
          USB product ID of the NFC reader, as reported by `lsusb` (the
          second half of the `id` column).
        '';
      };
    };

    remote = {
      enable = lib.mkEnableOption "remote control of the live session over RDP";

      port = lib.mkOption {
        type = lib.types.port;
        default = 3389;
        description = "TCP port the RDP server listens on.";
      };

      username = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Username remote clients authenticate with. Defaults to
          {option}`gewis.servicePc.user`. It is only an RDP credential and has
          nothing to do with the system account.
        '';
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression "config.sops.secrets.rdpPassword.path";
        description = ''
          File holding the password remote clients authenticate with. Must be
          readable by {option}`gewis.servicePc.user`.
        '';
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Open {option}`port` on every interface. Prefer
          {option}`firewallInterfaces` — an RDP server reachable from the whole
          LAN is a bigger target than one reachable over the mesh.
        '';
      };

      firewallInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = lib.literalExpression ''
          [ config.gewis.netbird.interface ]
        '';
        description = "Interfaces to open {option}`port` on.";
      };
    };
  };
}
