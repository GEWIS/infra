{ ... }:
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/xvda";
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
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };

  disko.devices.disk.data = {
    type = "disk";
    device = "/dev/xvdb";
    content = {
      type = "gpt";
      partitions = {
        garage = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "xfs";
            mountpoint = "/var/lib/garage";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };
}
