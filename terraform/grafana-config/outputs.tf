output "organizations" {
  description = "Per tenant: the Grafana organization ID and the X-Scope-OrgID its datasources send."
  value = {
    for tenant in local.tenants : tenant => {
      org_id = grafana_organization.tenant[tenant].org_id
      scope  = local.scope[tenant]
    }
  }
}
