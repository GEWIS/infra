{
  config,
  lib,
  pkgs,
  ...
}:

let
  kioskLauncher = pkgs.writeShellScript "kiosk-launch" ''
    url="$(cat ${config.sops.secrets.kioskUrl.path})"
    until ${pkgs.curl}/bin/curl -sSf --max-time 5 -o /dev/null "$url"; do
      sleep 2
    done
    exec env MOZ_ENABLE_WAYLAND=1 ${pkgs.firefox}/bin/firefox \
      --kiosk \
      --profile "$(mktemp -d)" \
      "$url"
  '';
in
{
  users = {
    allowNoPasswordLogin = true;

    groups.gewis.gid = 1000;
    users.gewis = {
      isNormalUser = true;
      description = "GEWIS kiosk";
      uid = 1000;
      group = "gewis";
      hashedPassword = "";
      extraGroups = [
        "video"
        "audio"
      ];
    };

    users.cbc = {
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets.cbcPassword.path;
      extraGroups = [ "wheel" ];
    };
  };

  security.sudo.wheelNeedsPassword = false;

  services.cage = {
    enable = true;
    user = "gewis";
    program = "${kioskLauncher}";
    extraArguments = [ "-d" ];
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="input", ENV{ID_INPUT_MOUSE}=="1", ENV{LIBINPUT_IGNORE_DEVICE}="1"
  '';

  systemd.services.cage-tty1 = {
    startLimitIntervalSec = 60;
    startLimitBurst = 10;
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.services."autovt@tty1".enable = false;

  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  environment.systemPackages = [ pkgs.firefox ];

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "corefonts"
      "vista-fonts"
    ];

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
      liberation_ttf
      dejavu_fonts
      ubuntu-classic
      corefonts
      font-awesome
      vista-fonts
    ];
    fontconfig = {
      enable = true;
      defaultFonts = {
        serif = [
          "Noto Serif"
          "Liberation Serif"
        ];
        sansSerif = [
          "Noto Sans"
          "Liberation Sans"
        ];
        monospace = [
          "Noto Sans Mono"
          "Liberation Mono"
        ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };
}
