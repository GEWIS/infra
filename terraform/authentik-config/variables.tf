variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "authentik_url" {
  description = "authentik base URL. The gateway is published on 8443, and the port is part of the OIDC issuer, so it belongs here."
  type        = string
  default     = "https://authentik.cbc.gewis.nl:8443"
}

variable "kubeconfig_path" {
  description = "Kubeconfig used to read the authentik API token from the cluster. Defaults to the repository's .kube/config, which .envrc mints."
  type        = string
  default     = null
}

variable "bao_address" {
  description = "OpenBao API address."
  type        = string
  default     = "https://openbao.cbc.gewis.nl:8443"
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

variable "ad_user_filter" {
  description = "LDAP filter selecting the users authentik may sync, verbatim from the Active Directory side. Restricts the source to holders of the logon privilege rather than the whole directory."
  type        = string
}
