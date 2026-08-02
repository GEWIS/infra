{
  config,
  pkgs,
  lib,
  ...
}:
let
  meshInterface = config.services.netbird.clients.${config.gewis.netbird.client}.interface;
in
{
  services.printing = {
    enable = true;
    drivers = lib.singleton (
      pkgs.linkFarm "drivers" [
        {
          name = "share/cups/model/PSGEWIS1.ppd";
          path = ./assets/PSGEWIS1.ppd;
        }
        {
          name = "share/cups/model/PSGEWIS3.ppd";
          path = ./assets/PSGEWIS3.ppd;
        }
      ]
    );
  };

  hardware.printers = {
    ensurePrinters = [
      {
        name = "PSGEWIS1";
        deviceUri = "ipp://10.0.0.10:631/ipp/print";
        model = "PSGEWIS1.ppd";
      }
      {
        name = "PSGEWIS3";
        deviceUri = "ipp://10.0.0.11:631/ipp/print";
        model = "PSGEWIS3.ppd";
      }
    ];
    ensureDefaultPrinter = "PSGEWIS1";
  };

  services.geprint = {
    enable = true;
    address = "0.0.0.0";
    port = 8080;
    openFirewall = false;
  };

  networking.firewall.interfaces.${meshInterface}.allowedTCPPorts = [ 8080 ];
}
