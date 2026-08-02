variable "target_host" {
  description = "Reachable address of the host; the operator owns that reachability, whether on-prem or via a NetBird routing peer."
  type        = string
}

variable "target_user" {
  description = "SSH user nixos-anywhere connects as."
  type        = string
  default     = "root"
}

variable "instance_id" {
  description = "Opaque identity of the underlying machine; changing it forces a full reinstall instead of a rebuild."
  type        = string
}

variable "nixos_system_attr" {
  description = "Flake attribute producing the system toplevel."
  type        = string
}

variable "nixos_partitioner_attr" {
  description = "Flake attribute producing the disko script."
  type        = string
}

variable "extra_files_script" {
  description = "Script whose working directory is copied onto the target's / before install."
  type        = string
  default     = null
}

variable "extra_environment" {
  description = "Environment passed to the install/build steps; carries the host age key."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "build_on_remote" {
  description = "Build the NixOS configuration on the target instead of locally."
  type        = bool
  default     = false
}
