{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; }) cfg sessionUnit;

  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.nfcpy
  ]);

  nfcReaderScript = pkgs.writeShellScript "service-pc-nfc-reader" ''
    set -eu
    exec env YDOTOOL_SOCKET=${config.environment.variables.YDOTOOL_SOCKET} \
      ${lib.getExe' pythonEnv "python3"} -u ${./assets/nfc-reader.py} \
      usb:${cfg.nfcReader.vendorId}:${cfg.nfcReader.productId} \
      ${lib.getExe' pkgs.ydotool "ydotool"}
  '';
in
{
  config = lib.mkIf cfg.enable {
    # The kernel's own pn533_usb driver claims the ACR122U (072f:2200) for
    # the in-kernel NFC subsystem before nfcpy's libusb-based open ever
    # gets a chance, so every open fails with "Device or resource busy".
    boot.blacklistedKernelModules = lib.mkIf cfg.nfcReader.enable [ "pn533_usb" ];

    services.udev.extraRules = lib.mkIf cfg.nfcReader.enable ''
      SUBSYSTEM=="usb", ATTRS{idVendor}=="${cfg.nfcReader.vendorId}", ATTRS{idProduct}=="${cfg.nfcReader.productId}", TAG+="uaccess"
    '';

    # Types via ydotool (a virtual /dev/uinput keyboard) rather than X11
    # XTEST: Mutter gates XTEST fake input from XWayland clients behind an
    # "Allow Remote Interaction" consent dialog with no unattended bypass,
    # which is a non-starter for an unattended kiosk. ydotool looks like a
    # real input device to the kernel, so nothing needs to approve it.
    programs.ydotool.enable = lib.mkIf cfg.nfcReader.enable true;

    users.users.${cfg.user}.extraGroups = lib.mkIf cfg.nfcReader.enable [
      config.programs.ydotool.group
    ];

    systemd.user.services = lib.mkIf cfg.nfcReader.enable {
      service-pc-nfc-reader = sessionUnit {
        description = "NFC tag reader for the service-PC session";
        exec = "${nfcReaderScript}";
        wmClass = "service-pc-nfc-reader";
        workspace = null;
        monitor = null;
      };
    };
  };
}
