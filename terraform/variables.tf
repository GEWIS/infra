variable "host_age_key" {
  description = "Host age private key (AGE-SECRET-KEY-...), inlined into the nixos-anywhere extra-files script so sops-nix can decrypt secrets on first boot. Export via TF_VAR_host_age_key; never commit it."
  type        = string
  sensitive   = true
}
