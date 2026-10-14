# App access

An app's people reach their namespaces two ways: through [Kite](kite.md) and with
`kubectl` over NetBird. Both are generated from one list, so a group never has
one without the other.

Kite cannot take its roles from Kubernetes objects. It reads one config file and
talks to the apiserver as its own service account, so a RoleBinding does nothing
for Kite. That is why the list lives here, next to Kite's config, and not in
`k8s-apps`.

## The list

`flux/50_apps/kite/app-access.yaml` holds the ConfigMap `app-access`:

```yaml
adminGroups:
  - "Netbird - K3s Hosts - SSH Access"
apps:
  - name: sudosos
    group: "ABC - POS"
    namespaces: [sudosos-prod, sudosos-test]
```

An app's `group` is used as-is in two places: as the AD group in the `groups`
claim Kite gets from Keycloak, and as the group the RoleBindings below bind,
which a request through the ClusterProxy carries. Both must be exactly this
name.

Kite and NetBird see different AD groups. Kite's claim holds the groups under
`OU=Groups`. NetBird's holds only the `netbird` client roles, which come from
`OU=NetBird,OU=Applications,OU=Permission Groups`. An app group under
`OU=Groups` therefore works in Kite and renders its RoleBindings, but reaches
the proxy only once NetBird also receives it.

`adminGroups` are NetBird groups the proxy may impersonate without a namespace
limit. Their rights come from the `cluster-admins` ClusterRoleBinding in
`flux/30_config/rbac/`, in the `config` layer. They come from the NetBird OU,
since the proxy passes on only the caller's NetBird groups.

## What one entry produces

The local chart `charts/app-access` is installed twice from that ConfigMap:

| Release | Layer | Renders |
| --- | --- | --- |
| `kite-config` (`render: kiteConfig`) | `apps` | Secret `kite/kite-roles`: Kite's whole config, with `<name>-read` (`get`, `log`) and `<name>-pods` (`exec`, `delete` on pods) mapped to `group` |
| `app-access` (`render: access`) | `access` | per namespace a Role and RoleBinding `<name>-access` for `Group: <group>`: read everything, `pods/exec`, delete pods; plus the NetBird ClusterProxy, which may impersonate `adminGroups` and every app `group` |

The split exists because a RoleBinding needs its namespace, and app namespaces
come from `k8s-apps` in `external-apps`. Only the `access` layer waits for
that, so Kite itself does not. A namespace that does not exist yet fails the
`app-access` release visibly; it recovers once the app arrives.

## kubectl over NetBird

The ClusterProxy `gewis` in `netbird-operator` runs a NetBird peer that joins the
NetBird group `k8s-api` and forwards to `https://kubernetes.default.svc` as
ServiceAccount `clusterproxy-gewis`. `k8s-api` is only the peer's own group, used
in NetBird policies; it is not sent to the apiserver. The account may only
impersonate, so a request runs as the caller's NetBird user with their groups,
and the RoleBindings above decide what it may do.

The account may impersonate any user and the groups in both lists. That makes
the proxy pod a trusted component, like the Flux controllers: whoever controls
it can act as almost any user.

The chart also renders a `Group` `k8s-api` in `netbird-operator`, and the
ClusterProxy refers to it with `localRef`, so the operator creates the NetBird
group itself. A plain `name:` reference would instead require the group to
exist in NetBird already. Who can reach the proxy at all is a NetBird policy
to `k8s-api`, managed in the NetBird dashboard; today only
`Netbird - K3s Hosts - SSH Access` has one.
