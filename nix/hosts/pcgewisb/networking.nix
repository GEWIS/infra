_: {
  # GNOME turns NetworkManager on; left managed, it would put its DHCP
  # profile on the controller port instead of the static address below.
  networking.networkmanager.unmanaged = [ "interface-name:enp2s0" ];

  networking.interfaces.enp2s0 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "169.254.0.1";
        prefixLength = 16;
      }
    ];
  };
}
