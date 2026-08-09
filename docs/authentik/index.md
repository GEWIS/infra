# authentik

Identity provider at `https://authentik.cbc.gewis.nl:8443`, reconciled by the
`apps` layer. It exists to be the OIDC front door for things that have no
business holding their own user list — OpenBao first, more later.

Users are not local to it. The accounts come from GEWIS Active Directory over
LDAP, which is also what sits underneath Keycloak, so authentik is a policy and
protocol layer rather than a second directory.

Nothing here configures authentik itself. Providers, applications, groups and
the LDAP source belong to `terraform/authentik-config`, which authenticates with
the bootstrap token this deployment seals.
