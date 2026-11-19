# Sealed Secrets

The controller runs from `flux/10_sealed-secrets/`. Its sealing key pair is
pinned: `terraform/20_talos-bootstrap/sealed-secrets.tf` writes it from
`secrets/sealed-secrets.yaml`, and `keyrenewperiod: "0"` stops the controller
from generating new keys. The certificate therefore never changes.

## Public certificate

The certificate is published at
`https://sealed-secrets.gewis.nl/v1/cert.pem`, so sealing needs neither cluster
access nor the sops key:

```sh
kubeseal --cert https://sealed-secrets.gewis.nl/v1/cert.pem --format yaml \
  < /tmp/secret.yaml > sealed-secret.yaml
```

Write the plaintext input under `/tmp`, never in the working tree.

The route is the chart's own `Ingress` (`ingress:` in the HelmRelease values),
served by the default `traefik` IngressClass. Its path is `Exact`, so the
controller's `/v1/verify` and `/v1/rotate` stay unreachable from outside. It
lands on `websecure`, the default entry point, whose TLS is on for every router,
so it needs no Traefik annotations. TLS comes from the default TLS store, see
[Ingress (Traefik)](traefik.md); the DNS record comes from external-dns's
`ingress` source, see [DNS](dns.md).
