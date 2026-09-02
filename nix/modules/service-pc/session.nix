{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; })
    cfg
    placed
    needsPlacement
    ;

  extensions = [
    "no-overview@fthx"
  ]
  ++ lib.optional needsPlacement "window-calls@domandoman.xyz";
in
{
  config = lib.mkIf cfg.enable {
    assertions = lib.concatMap (p: [
      {
        assertion = !(p.workspace != null && p.monitor != null);
        message = ''
          ${p.what} sets both `workspace` and `monitor`; a window is placed on
          one or the other.
        '';
      }
      {
        assertion = p.monitor != null -> cfg.multiMonitor;
        message = ''
          ${p.what}.monitor needs gewis.servicePc.multiMonitor = true.
        '';
      }
      {
        assertion = p.workspace != null -> p.workspace <= cfg.workspaces;
        message = ''
          ${p.what}.workspace is ${toString p.workspace}, but
          gewis.servicePc.workspaces is only ${toString cfg.workspaces}.
        '';
      }
    ]) placed;

    users = {
      groups.${cfg.user} = lib.optionalAttrs (cfg.uid != null) { gid = cfg.uid; };

      users.${cfg.user} = {
        isNormalUser = true;
        description = "GEWIS service-PC session";
        group = cfg.user;
        extraGroups = [
          "video"
          "audio"
        ];
      }
      // lib.optionalAttrs (cfg.uid != null) { inherit (cfg) uid; };
    };

    services.displayManager = {
      gdm.enable = true;
      defaultSession = "gnome";
      autoLogin = {
        enable = true;
        inherit (cfg) user;
      };
    };

    services.desktopManager.gnome = {
      enable = true;

      extraGSettingsOverridePackages = [
        pkgs.mutter
        pkgs.gnome-settings-daemon
      ];

      extraGSettingsOverrides = lib.concatStringsSep "\n" (
        [
          # Pins the workspace count so windows can be placed by index.
          ''
            [org.gnome.mutter]
            dynamic-workspaces=false

            [org.gnome.desktop.wm.preferences]
            num-workspaces=${toString cfg.workspaces}
          ''
        ]
        ++ lib.optional (extensions != [ ]) ''
          [org.gnome.shell]
          enabled-extensions=[${lib.concatMapStringsSep "," (e: "'${e}'") extensions}]
        ''
        ++ lib.optional (cfg.touch.enable && cfg.touch.onScreenKeyboard) ''
          [org.gnome.desktop.a11y.applications]
          screen-keyboard-enabled=true
        ''
        # A service PC is never locked: it shows one thing, nobody is sitting
        # at it to unlock it, and the session account has no password anyway.
        ++ [
          ''
            [org.gnome.desktop.session]
            idle-delay=uint32 0

            [org.gnome.desktop.screensaver]
            lock-enabled=false
            idle-activation-enabled=false

            [org.gnome.settings-daemon.plugins.power]
            sleep-inactive-ac-type='nothing'
            sleep-inactive-battery-type='nothing'
          ''
        ]
      );
    };

    environment.systemPackages = [
      pkgs.gnomeExtensions.no-overview
    ]
    ++ lib.optional needsPlacement pkgs.gnomeExtensions.window-calls;

    systemd.targets = {
      sleep.enable = false;
      suspend.enable = false;
      hibernate.enable = false;
      hybrid-sleep.enable = false;
    };
  };
}
