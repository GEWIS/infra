{ config, lib, ... }:
let
  cfg = config.gewis.nvidia;
in
{
  options.gewis.nvidia.enable = lib.mkEnableOption "NVIDIA's driver with the open kernel modules (Turing or newer)";

  config = lib.mkIf cfg.enable {
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "nvidia-x11" ];

    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      open = true;
      nvidiaSettings = false;
    };
  };
}
