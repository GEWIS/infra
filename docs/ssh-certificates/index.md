# SSH certificates

OpenBao is a certificate authority for SSH user keys. A member of the Application
Hosting Team logs in to OpenBao through authentik, has their own public key signed,
and gets a certificate that a host accepts for five hours. Nobody's key has to be
added to a host, and nothing has to be removed when someone leaves: their next
certificate is simply refused.

| Piece | Where |
| --- | --- |
| `ssh` secrets engine mount | `terraform/40_openbao-config` |
| CA, signing role `admin`, policy `ssh-sign-admin` | `terraform/50_ssh-certificates` |
| `ssh-sign-admin` on the OIDC role `authentik` | `terraform/50_authentik-config` — see [OpenBao](../cluster/openbao.md#people-log-in-through-authentik) |
| hosts trusting the CA | `nix/modules/ssh-user-ca.nix`, `gewis.sshUserCa.enable` |

Only **s3-01** enables it so far. The service PCs run NetBird's own SSH server, see
[NetBird](signing.md#over-the-mesh-or-the-lan) for why that needs thought first.
Talos nodes have no SSH at all.

The certificate names the **account** — `root` or `cbc` — and its key ID names the
**person**, `oidc-<username>`, which sshd logs on every login. That is enough while
one team has the same access everywhere; giving different groups different hosts
would mean switching to principals that each host maps to its accounts through
`AuthorizedPrincipalsFile`.

The other ways in stay: the break-glass key in root's `authorized_keys` on
s3-01 (see [s3-01](../s3-01/index.md)) and the `cbc` password on the service PCs.

- [The CA and the role](ca.md)
- [Hosts](hosts.md)
- [Signing and logging in](signing.md)
