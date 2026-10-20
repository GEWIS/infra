locals {
  realm = "GEWISWG"

  webhost_prod_hosts = [
    "9eglinster.gewis.nl",
    "9eglinster-admin.gewis.nl",

    "abc.gewis.nl",
    "abc-admin.gewis.nl",

    "athena.gewis.nl",
    "yourdomain.gewis.nl",

    "avico.gewis.nl",

    "bac.gewis.nl",
    "bac-admin.gewis.nl",

    "cib.personal.gewis.nl",

    "co.personal.gewis.nl",

    "ceb.personal.gewis.nl",
    "ceb-admin.personal.gewis.nl",

    "cbc-bbq.gewis.nl",

    "boom.gewis.nl",
    "boom-admin.gewis.nl",

    "defi.gewis.nl",
    "defi-admin.gewis.nl",

    "gehack.gewis.nl",
    "gehack-admin.gewis.nl",

    "gezwem.gewis.nl",
    "gezwem-admin.gewis.nl",

    "intro.gewis.nl",
    "intro-admin.gewis.nl",

    "mta-sts.gewis.nl",

    "odc.gewis.nl",
    "odc-admin.gewis.nl",

    "pm.personal.gewis.nl",

    "rink.personal.gewis.nl",

    "secr.personal.gewis.nl",

    "ssg.gewis.nl",
    "ssg-admin.gewis.nl",

    "static.gewis.nl",
    "static-admin.gewis.nl",

    "stijl.gewis.nl",

    "vz.personal.gewis.nl",
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

  oidc_clients = {
    kite = {
      client_id     = "kite"
      namespace     = "kite"
      redirect_uris = ["https://kite.gewis.nl/api/auth/callback"]
    }
    grafana = {
      client_id     = "grafana-prod"
      namespace     = "observability"
      redirect_uris = ["https://grafana.gewis.nl/login/generic_oauth"]
    }
  }

  client_read_policies = merge(
    { for name, client in local.forward_auth_clients : name => { namespace = client.namespace, policy = vault_policy.forward_auth_client_read[name].name } },
    { for name, client in local.oidc_clients : name => { namespace = client.namespace, policy = vault_policy.oidc_client_read[name].name } },
  )

  namespace_policies = {
    for namespace in distinct([for client in local.client_read_policies : client.namespace]) : namespace => [
      for client in local.client_read_policies : client.policy if client.namespace == namespace
    ]
  }
}
