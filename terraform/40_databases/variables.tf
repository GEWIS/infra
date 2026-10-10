variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
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

variable "postgres_host" {
  description = "Name of the Postgres primary, for tofu and every client. Its certificate is issued for this name, and it resolves only through the cluster resolver."
  type        = string
  default     = "postgres.cbc.gewis.nl"
}

variable "postgres_port" {
  description = "Port of the Postgres primary on its LoadBalancer address."
  type        = number
  default     = 5432
}

variable "mariadb_host" {
  description = "Name of the MariaDB primary, for tofu and every client. Its certificate is issued for this name, and it resolves only through the cluster resolver."
  type        = string
  default     = "mariadb.cbc.gewis.nl"
}

variable "mariadb_port" {
  description = "Port of the MariaDB primary on its LoadBalancer address."
  type        = number
  default     = 3306
}

variable "kubeconfig_path" {
  description = "Kubeconfig used to read the provisioner credentials from the cluster. Defaults to the repository's .kube/config, which .envrc mints."
  type        = string
  default     = null
}
