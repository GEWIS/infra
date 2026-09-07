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
    ps.pyautogui
  ]);

  nfcReaderScript = pkgs.writeShellScript "service-pc-nfc-reader" ''
    set -eu
    exec ${lib.getExe' pythonEnv "python3"} -u ${./assets/nfc-reader.py} usb:${cfg.nfcReader.vendorId}:${cfg.nfcReader.productId}
  '';
in
{
  config = lib.mkIf cfg.enable {
    services.udev.extraRules = lib.mkIf cfg.nfcReader.enable ''
      SUBSYSTEM=="usb", ATTRS{idVendor}=="${cfg.nfcReader.vendorId}", ATTRS{idProduct}=="${cfg.nfcReader.productId}", TAG+="uaccess"
    '';

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
