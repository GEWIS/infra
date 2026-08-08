variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "garage_endpoint" {
  description = "Garage Admin API endpoint. Reachable from the campus LAN only; the host has no WAN leg."
  type        = string
  default     = "http://10.82.50.100:3903"
}

variable "garage_admin_token" {
  description = "Garage Admin API bearer token. Exported from secrets/s3-01.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
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
