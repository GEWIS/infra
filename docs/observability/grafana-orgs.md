# Grafana organizations cannot be provisioned from the cluster

Grafana OSS has no declarative org mechanism, and this is not an oversight to
route around:

- The Helm chart provisions datasources and dashboards, never orgs.
- `grafana-operator` v5 has CRDs for dashboards, datasources, folders, service
  accounts and alerting — none for orgs.
- Grafana's own `grizzly` has handlers for everything except orgs.
- The new app-platform IAM API (`iam.grafana.app/v0alpha1`) serves users, teams
  and service accounts. Orgs are absent; Cloud replaced them with stacks.

And an org that does not exist fails **silently**: `org_role_mapper.go` resolves
a non-numeric org through `GetByName` and, on a miss, logs `"Could not fetch
OrgID. Skipping."` — with `role_attribute_strict: true` it discards *the entire
mapping for every user*, not just the bad entry. `org_sync.go` likewise does
`if errors.Is(err, org.ErrOrgNotFound) { continue }`.

At login that surfaces as *"IdP did not return a role attribute, please contact
your administrator"*, which blames the wrong system. That string is the public
message of `errRoleAttributeStrictViolation`, and the check that raises it counts
*org* roles rather than claims:

```go
userInfo.OrgRoles = s.orgRoleMapper.MapOrgRoles(s.orgMappingCfg, externalOrgs, userInfo.Role)
if s.info.RoleAttributeStrict && len(userInfo.OrgRoles) == 0 {
    return errRoleAttributeStrictViolation.Errorf("could not evaluate any valid roles using IdP provided data")
}
```

So the `groups` claim can be perfect and every group name can match, and the
login still fails because each mapped org was skipped. The accompanying
`"Failed to extract role"` warnings about `role_attribute_path` are a separate,
**non-fatal** path: with no `role_attribute_path` set, the role comes from
`org_mapping` instead, and the caller logs that failure at warn level and carries
on.

So orgs and their datasources are owned by `terraform/grafana-config`, in the
same style as `garage-buckets` and `openbao-config`. Both chart sidecars are
disabled, so everything org-scoped has exactly one owner.

Dashboards follow the same rule, and the chart's dashboard sidecar is not how they
get there. Its provider hardcodes `orgid: 1`, and one provider means one
organization — so a single sidecar can never serve seven tenants, and org 1 is
the empty `Main Org.` that no role maps into. Enabling it would provision every
`grafana_dashboard`-labelled ConfigMap into an organization nobody can see,
silently. Pointing it at CBC instead would hardcode a tofu-assigned,
auto-incremented org ID into a HelmRelease. So dashboards sit beside the
datasources in the tofu root — see [Dashboards](dashboards.md).
