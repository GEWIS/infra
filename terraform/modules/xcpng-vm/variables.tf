variable "pool_name_label" {
  description = "name_label of the XCP-ng pool."
  type        = string
}

variable "template_name_label" {
  description = "name_label of the VM template to clone (bootstrap OS; replaced by nixos-anywhere)."
  type        = string
}

variable "network_name_label" {
  description = "name_label of the network / VLAN to attach."
  type        = string
}

variable "sr_name_label" {
  description = "name_label of the Storage Repository for the disks."
  type        = string
}

variable "expected_ip_cidr" {
  description = "CIDR the VM's first NIC must report an address from before create finishes. This is how the address is discovered: the guest agent reports it, the provider blocks until it lands in this range, and vm_ipv4 then carries it to nixos-anywhere. Requires a working guest agent in the bootstrap OS. Empty disables the wait and leaves vm_ipv4 null."
  type        = string
  default     = ""
}

variable "vm_name" {
  description = "name_label for the VM."
  type        = string
}

variable "cpus" {
  description = "Number of vCPUs."
  type        = number
  default     = 4
}

variable "memory_gib" {
  description = "RAM in GiB."
  type        = number
  default     = 8
}

variable "root_disk_gib" {
  description = "Root disk size in GiB (must be >= the template's root disk)."
  type        = number
  default     = 40
}

variable "data_disk_gib" {
  description = "Extra data disk size in GiB."
  type        = number
  default     = 100
}

variable "ssh_authorized_key" {
  description = "SSH public key injected via cloud-init so nixos-anywhere can reach the bootstrap OS."
  type        = string
  default     = ""
}

variable "mac_address" {
  description = "Fixed MAC for the NIC, so the VM keeps one stable L2 identity across rebuilds and the DHCP lease is predictable."
  type        = string
  default     = ""
}

variable "clone_type" {
  description = "\"full\" (independent copy, needed across hosts/SRs) or \"fast\" (CoW)."
  type        = string
  default     = "full"
}

variable "auto_poweron" {
  description = "Start the VM after a host reboot."
  type        = bool
  default     = true
}

variable "hvm_boot_firmware" {
  description = "\"uefi\" or \"bios\". Ubuntu cloud images need uefi."
  type        = string
  default     = "uefi"
}
