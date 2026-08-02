output "vm_ipv4" {
  description = "Primary IPv4 the guest agent reported, discovered during create by waiting for an address inside expected_ip_cidr. This is what nixos-anywhere connects to."
  value       = try(xenorchestra_vm.this.network[0].ipv4_addresses[0], null)
}

output "vm_id" {
  description = "Xen Orchestra VM UUID."
  value       = xenorchestra_vm.this.id
}
