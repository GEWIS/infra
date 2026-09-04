{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; })
    cfg
    placement
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
        Unprivileged user the graphical session, the browser, the extra apps
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

    touch = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          This host is a touchscreen with no keyboard or mouse.
        '';
      };

      onScreenKeyboard = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable GNOME's on-screen keyboard.";
      };
    };

    browser = {
      enable = lib.mkEnableOption "Firefox pointed at a fixed URL";

      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "https://sudosos.gewis.nl/pos";
        description = ''
          URL to open. Mutually exclusive with {option}`urlFile`; use that one
          if the URL contains an API key or other secret.
        '';
      };

      urlFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression "config.sops.secrets.kioskUrl.path";
        description = ''
          File read at launch to get the URL. Mutually exclusive with
          {option}`url`.
        '';
      };

      kiosk = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run the browser fullscreen in kiosk mode
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
          [ config.services.netbird.clients.netbird.interface ]
        '';
        description = "Interfaces to open {option}`port` on.";
      };
    };
  };
}
