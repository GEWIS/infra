# External proxy

`flux/50_apps/external-proxy/` publishes services that run on VMs outside the
cluster, carried over from the previous cluster's `infra/traefik/external-proxy/`.
Everything lives in the `external-proxy` namespace.

All three hosts are NetBird peers and are reached only over NetBird, never by LAN
address: each has a `NetworkEgress` that creates a Service of the same name with
one port per app, and the operator points that Service's EndpointSlices at the
`lan` [NetworkRouter](netbird.md#operator-and-network-router) pods, which forward
over NetBird to the peer's NetBird DNS name.

| Host | Target |
| --- | --- |
| gewiscontainer | `gewiscontainer.net.nb.gewis.nl` |
| gewismail | `gewismail.net.nb.gewis.nl` |
| gewisweb | `gewisweb.net.nb.gewis.nl` |

The router pods resolve these names through the NetBird client's DNS, which only
answers for peers the router may reach.

A new app needs a port on its host's `NetworkEgress` (TCP only, name at most 15
characters) and a rule on the matching `IngressRoute`.

## NetBird policy

NetBird drops the traffic unless a policy allows it, and the policy is managed in
the NetBird dashboard. The router pods join a NetBird group whose name the
operator generates from the router's UID; read it with

```sh
kubectl -n netbird-operator get groups.netbird.io networkrouter-lan -o jsonpath='{.spec.name}'
```

The policy runs from that group to the groups of the gewiscontainer, gewismail
and gewisweb peers, TCP, on every port listed in `gewiscontainer.yaml`,
`gewismail.yaml` and `gewisweb.yaml`.

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
