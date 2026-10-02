resource "vault_ssh_secret_backend_ca" "ssh" {
  backend              = "ssh"
  generate_signing_key = true
  key_type             = "ed25519"
}

resource "vault_ssh_secret_backend_role" "admin" {
  backend                 = "ssh"
  name                    = "admin"
  key_type                = "ca"
  allow_user_certificates = true

  allowed_users = "root,cbc"
  key_id_format = "{{token_display_name}}"

  allowed_extensions = "permit-pty"
  default_extensions = {
    permit-pty = ""
  }

  ttl     = "5h"
  max_ttl = "5h"
}

resource "vault_policy" "sign_admin" {
  name = "ssh-sign-admin"

  policy = <<-EOT
    path "ssh/sign/${vault_ssh_secret_backend_role.admin.name}" {
      capabilities = ["update"]
    }
  EOT
}
