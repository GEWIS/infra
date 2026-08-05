variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "talos_secrets" {
  description = "Talos PKI bundle, the YAML that `talosctl gen secrets` produces. Exported from secrets/talos.yaml by .envrc as TF_VAR_talos_secrets. Fed only into ephemeral resources and write-only inputs, so no CA private key is ever written to the state file."
  type        = string
  sensitive   = true
}
