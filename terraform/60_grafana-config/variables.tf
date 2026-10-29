variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "grafana_url" {
  description = "Grafana base URL."
  type        = string
  default     = "https://grafana.gewis.nl"
}

variable "kubeconfig_path" {
  description = "Kubeconfig used to read the Grafana admin credentials from the cluster. Defaults to the repository's .kube/config: the NetBird proxy kubeconfig, or a mint-creds break-glass certificate while one is valid."
  type        = string
  default     = null
}
