# The one secret, and where it lives

`grafana-auth` carries `admin-user`, `admin-password`, `keycloak-client-id` and
`keycloak-client-secret`. It is a SealedSecret next to the chart that consumes
it, and it is the **only** copy: Grafana mounts it, and
`terraform/grafana-config` reads it back out of the cluster at apply time.

Sealing is offline — the pinned key pair lives in `secrets/sealed-secrets.yaml`,
so no cluster access is needed to produce the ciphertext:

```sh
sops -d --extract '["tls_crt"]' secrets/sealed-secrets.yaml > /tmp/sealing.crt
kubeseal --cert /tmp/sealing.crt --format yaml < /tmp/grafana-auth.yaml \
  > flux/apps/observability/grafana/auth-sealed-secret.yaml
```

Write the plaintext input under `/tmp`, never in the working tree — nothing in
`.gitignore` would catch it, and a rule broad enough to catch it would also
shadow the sealed output.

Rotating the admin password is one resealed file. The tofu root picks the new
value up on its next apply because it never stored the old one.
