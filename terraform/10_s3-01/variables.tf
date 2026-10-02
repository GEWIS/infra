variable "host_age_key" {
  description = "Host age private key (AGE-SECRET-KEY-...), inlined into the nixos-anywhere extra-files script so sops-nix can decrypt secrets on first boot. Export via TF_VAR_host_age_key; never commit it."
  type        = string
  sensitive   = true
}

variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}
