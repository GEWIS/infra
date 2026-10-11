locals {
  realm = "GEWISWG"

  webhost_prod_hosts = [
    "abc.gewis.nl",
    "abc-admin.gewis.nl",
    "gehack.gewis.nl",
    "cbc-bbq.gewis.nl",
    "static.gewis.nl",
    "stijl.gewis.nl",
    "vz.personal.gewis.nl",
    "secr.personal.gewis.nl",
    "pm.personal.gewis.nl",
    "cib.personal.gewis.nl",
    "co.personal.gewis.nl",
    "ceb.personal.gewis.nl",
    "mta-sts.gewis.nl",
    "9eglinster.gewis.nl",
    "athena.gewis.nl",
    "defi.gewis.nl",
    "avico.gewis.nl",
    "boom.gewis.nl",
    "gezwem.gewis.nl",
    "intro.gewis.nl",
    "linkinbio.gewis.nl",
    "odc.gewis.nl",
    "ssg.gewis.nl",
    "bac.gewis.nl",
    "bac-admin.gewis.nl",
  ]

  forward_auth_clients = {
    webhost-prod = {
      namespace     = "webhost-prod"
      redirect_uris = [for host in local.webhost_prod_hosts : "https://${host}/admin/oidc/callback"]
    }
    webhost-test = {
      namespace     = "webhost-test"
      redirect_uris = ["https://webhost.test.gewis.nl/admin/oidc/callback"]
    }
  }

  forward_auth_namespace_policies = {
    for namespace in distinct([for client in local.forward_auth_clients : client.namespace]) : namespace => [
      for name, client in local.forward_auth_clients :
      vault_policy.forward_auth_client_read[name].name if client.namespace == namespace
    ]
  }
}
