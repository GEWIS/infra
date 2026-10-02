output "node_addresses" {
  description = "Static (DHCP-reserved) address per Talos node."
  value       = { for name, node in local.nodes : name => node.ip }
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint. Publish A records for this name to every node address."
  value       = local.cluster_endpoint
}
