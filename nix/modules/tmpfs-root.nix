{ config, lib, ... }:
let
  cfg = config.gewis.tmpfsRoot;
in
{
  options.gewis.tmpfsRoot = {
    enable = lib.mkEnableOption "a tmpfs root with /nix and /persist as btrfs subvolumes on one UEFI disk";

    device = lib.mkOption {
      type = lib.types.str;
      default = "/dev/nvme0n1";
      description = "Disk that disko partitions into the ESP and the btrfs volume.";
    };

    size = lib.mkOption {
      type = lib.types.str;
      default = "2G";
      description = "Size of the tmpfs root.";
    };
  };

  config = lib.mkIf cfg.enable {
    gewis.persistence.enable = true;

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = false;

    disko.devices = {
      disk.main = {
        device = lib.mkDefault cfg.device;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            disk = {
              size = "100%";
              content = {
                type = "btrfs";
                subvolumes = {
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "/persist" = {
                    mountpoint = "/persist";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                };
              };
            };
          };
        };
      };

      nodev."/" = {
        fsType = "tmpfs";
        mountOptions = [
          "size=${cfg.size}"
          "mode=755"
        ];
      };
    };
  };
}
