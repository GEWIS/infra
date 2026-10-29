variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "authentik_url" {
  description = "authentik base URL. It is part of every OIDC issuer authentik hands out."
  type        = string
  default     = "https://authentik.gewis.nl"
}

variable "kubeconfig_path" {
  description = "Kubeconfig used to read the authentik API token from the cluster. Defaults to the repository's .kube/config: the NetBird proxy kubeconfig, or a mint-creds break-glass certificate while one is valid."
  type        = string
  default     = null
}

variable "bao_address" {
  description = "OpenBao API address."
  type        = string
  default     = "https://openbao.gewis.nl"
}

variable "bao_role" {
  description = "OpenBao Kubernetes auth role to log in as."
  type        = string
  default     = "admin"
}

variable "bao_jwt" {
  description = "Kubernetes ServiceAccount token used to authenticate against OpenBao. Generate with: kubectl -n openbao create token openbao-admin."
  type        = string
  sensitive   = true
}

variable "ad_bind_password" {
  description = "Password for the Active Directory bind account. Exported from secrets/authentik.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}
