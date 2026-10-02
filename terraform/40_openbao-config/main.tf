resource "vault_mount" "kv" {
  path = "secret"
  type = "kv-v2"
}

resource "vault_kv_secret_v2" "example" {
  mount     = vault_mount.kv.path
  name      = "example/hello"
  data_json = jsonencode({ hello = "world" })
}
