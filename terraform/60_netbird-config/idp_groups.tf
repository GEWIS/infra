# TEMP: Replace these with the final groups once Authentik is set up
data "netbird_group" "cbc_admins" {
  name = "Netbird - K3s Hosts - SSH Access"
}

data "netbird_group" "gewis_members" {
  name = "Netbird vDesktop"
}
