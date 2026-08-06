variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "kubeconfig_path" {
  description = "Path to the cbc cluster kubeconfig. Defaults to the repo-local .kube/config that .envrc mints."
  type        = string
  default     = null
}
