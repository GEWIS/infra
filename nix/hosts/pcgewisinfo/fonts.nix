{ lib, pkgs, ... }:
{
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
