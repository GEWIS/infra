_: {

  services.dnsmasq = {
    resolveLocalQueries = false;
    enable = true;
    settings = {
      log-dhcp = true;

      bind-interfaces = true;
      interface = [
        "enp1s0"
      ];
      except-interface = "enp0s31f6";

      dhcp-authoritative = true;

      listen-address = [
        "10.0.0.1"
      ];

      dhcp-range = [
        "10.0.0.100,10.0.0.200,24h"
      ];

      dhcp-host = [
        "b0:0c:d1:de:f0:0d,10.0.0.10,infinite"
        "94:dd:f8:e5:86:4f,10.0.0.11,infinite"
      ];
    };
  };

  networking = {
    useDHCP = false;
    firewall.interfaces.enp1s0 = {
      allowedUDPPorts = [
        53
        67
      ];
      allowedTCPPorts = [
        53
        22
      ];
    };
    interfaces = {
      "enp0s31f6".useDHCP = true;
      "enp1s0" = {
        useDHCP = false;
        ipv4 = {
          addresses = [
            {
              address = "10.0.0.1";
              prefixLength = 24;
            }
          ];
        };
      };
    };
  };
}
