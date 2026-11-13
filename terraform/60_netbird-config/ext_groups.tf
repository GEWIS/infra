data "netbird_group" "all" {
  name = "All"
}

data "netbird_group" "k8s_api" {
  name = "k8s-api"
}

# This group may change dynamically
# For now we assume that this will not happen
data "netbird_group" "k8s_network_router" {
  name = "networkrouter-db5rrof5d8vs73833vog-bc59a9f7"
}