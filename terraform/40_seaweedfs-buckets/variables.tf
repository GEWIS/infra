variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "seaweedfs_endpoint" {
  description = "SeaweedFS S3 and IAM endpoint; both APIs share this port. Reachable from the campus LAN only; the host has no WAN leg."
  type        = string
  default     = "http://10.82.50.100:8333"
}

variable "seaweedfs_admin_access_key" {
  description = "Access key of the SeaweedFS admin identity. Exported from secrets/s3-01.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "seaweedfs_admin_secret_key" {
  description = "Secret key of the SeaweedFS admin identity. Exported from secrets/s3-01.yaml by .envrc; never set it by hand."
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
