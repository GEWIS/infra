variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "grafana_url" {
  description = "Grafana base URL."
  type        = string
  default     = "https://grafana.cbc.gewis.nl:8443"
}

variable "kubeconfig_path" {
  description = "Kubeconfig used to read the Grafana admin credentials from the cluster. Defaults to the repository's .kube/config, which .envrc mints."
  type        = string
  default     = null
}
