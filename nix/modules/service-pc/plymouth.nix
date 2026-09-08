{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; }) cfg;

  themeName = "gewis-service-pc";
  
  theme = pkgs.runCommand "service-pc-plymouth-theme" { } ''
    dir="$out/share/plymouth/themes/${themeName}"
    mkdir -p "$dir"
    cp ${./assets/plymouth-theme/gewis-service-pc.plymouth} "$dir/${themeName}.plymouth"
    cp ${./assets/plymouth-theme/gewis-service-pc.script} "$dir/${themeName}.script"
    cp ${./assets/wallpaper.png} "$dir/wallpaper.png"
    cp ${./assets/progress-track.png} "$dir/progress-track.png"
    cp ${./assets/progress-fill.png} "$dir/progress-fill.png"
  '';
in
{
  config = lib.mkIf cfg.enable {
    boot.plymouth = {
      enable = true;
      theme = themeName;
      themePackages = [ theme ];
    };

    boot.initrd.systemd.enable = lib.mkDefault true;

    boot.kernelParams = [
      "quiet"
      "splash"
      "loglevel=3"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];

    boot.consoleLogLevel = lib.mkDefault 0;
  };
}
