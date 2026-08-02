output "vm_ids" {
  description = "Xen Orchestra VM UUID per host."
  value       = { for name, vm in module.vm : name => vm.vm_id }
}

output "host_addresses" {
  description = "IPv4 discovered from the guest agent per host."
  value       = { for name, vm in module.vm : name => vm.vm_ipv4 }
}
