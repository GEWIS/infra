_: {
  networking.interfaces.enp1s0 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "169.254.0.1";
        prefixLength = 16;
      }
    ];
  };
}
