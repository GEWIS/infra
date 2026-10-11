variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "keycloak_url" {
  description = "Keycloak admin base URL. auth.gewis.nl routes only the public paths, so the admin API is reached on KC_HOSTNAME_ADMIN."
  type        = string
  default     = "https://auth-admin.gewis.nl"
}

variable "keycloak_client_secret" {
  description = "Secret of the opentofu service-account client in the master realm. Exported from secrets/keycloak.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
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
