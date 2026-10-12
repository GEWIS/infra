# External proxy

`flux/50_apps/external-proxy/` publishes services that run on VMs outside the
cluster, carried over from the previous cluster's `infra/traefik/external-proxy/`.
Everything lives in the `external-proxy` namespace.

All three hosts are reached on their LAN addresses: each has a selectorless
Service with a hand-written `EndpointSlice`, one port per app, like [S3](s3.md).

| Host | Service | Target |
| --- | --- | --- |
| gewiscontainer | `gewiscontainer-lan` | `10.82.50.119` |
| gewismail | `gewismail-lan` | `10.82.50.117` |
| gewisweb | `gewisweb-lan` | `10.82.50.120` |

The LAN addresses are hardcoded in `gewiscontainer.yaml`, `gewismail.yaml` and
`gewisweb.yaml` and must be DHCP reservations on the `10.82.50.0/24` DHCP server;
if a host's address changes, its routes fail until the `EndpointSlice` is
updated. A new app on these hosts needs a port on both the Service and the
`EndpointSlice`, with the same name, and a rule on the matching `IngressRoute`.

gewisweb publishes phpMyAdmin from Docker on `10.82.50.120:8081`, next to its
NetBird address; a container bound to that address does not start if the host
comes up with a different one.

The gewismail HTTPS backend has a self-signed certificate; `ServersTransport`
`gewismail` skips its verification.

## Hostnames

| Route | Hostnames | Backend |
| --- | --- | --- |
| `gewis` | `gewis.nl`, `www.gewis.nl` (redirect to the apex), `images.gewis.nl` | gewiscontainer `9210`, `9211` |
| `gewiscontainer` | `ivv`, `mail-api`, `wiki`, `gewiki`, `latex`, `pdf`, `supremum`, `docker`, `pgadmin`, `analytics`, `analytics.test`, `xoa`, `planka`, `vault`, `pkg`, `test` `.gewis.nl` | gewiscontainer, one port each |
| `docker-registry` | `docker-registry.gewis.nl` and `<committee>.docker-registry.gewis.nl` | gewiscontainer `9101`–`9112` |
| `gewismail` | `mail`, `webmail`, `lists` `.gewis.nl` | gewismail `443` (HTTPS), `8000` |
| `gewisweb` | `phpmyadmin.gewis.nl` | gewisweb `8081` |

`pgadmin`, `xoa` and `phpmyadmin` carry the `tue-only` Middleware: the TU/e range
and `100.64.0.0/10`, minus the WAF's `131.155.10.0/27` and `131.155.10.128/27`, so
a request relayed by the WAF is refused. The Middleware checks the connecting
address, which router02 passes through unchanged — see
[Client addresses](traefik.md#client-addresses).

None of the routes carries the external-dns annotation. Every hostname already
has a record, pointing at the WAF, router02 or the host itself, which external-dns
does not own; they all reach router02, which forwards `:443` here.
`mail.gewis.nl` resolves straight to gewismail, so it never passes either cluster.
