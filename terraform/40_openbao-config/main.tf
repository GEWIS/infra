resource "vault_mount" "kv" {
  path = "secret"
  type = "kv-v2"
}

resource "vault_kv_secret_v2" "example" {
  mount     = vault_mount.kv.path
  name      = "example/hello"
  data_json = jsonencode({ hello = "world" })
}

resource "vault_auth_backend" "oidc" {
  type        = "oidc"
  path        = "oidc"
  description = "Single sign-on through authentik, configured by 50_authentik-config."

  tune {
    listing_visibility = "unauth"
  }
}

resource "vault_mount" "ssh" {
  path        = "ssh"
  type        = "ssh"
  description = "SSH user certificate authority, configured by 50_ssh-certificates."
}
