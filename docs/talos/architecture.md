# How it fits together

Talos lives in its own OpenTofu root, `terraform/talos-hosts/`, with its own state
(`talos/terraform.tfstate`) and its own secret. It shares only the `xcpng-vm`
module with `s3-01`. The two roots reference nothing of each other's: the
cluster reaches Garage as an ordinary S3 client over the network, never through
tofu. Splitting them means a Talos apply cannot touch `s3-01`, and a Talos plan
skips `s3-01`'s three-minute closure build.

`s3-01` and `talos` both encrypt their state the same way, in the same bucket,
under the same passphrase from `secrets/tofu.yaml`. Each root is a separate
`tofu init`.
