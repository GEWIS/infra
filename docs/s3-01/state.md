# State

Remote, in Scaleway Object Storage (`nl-ams`), at
`tfstate/s3-01/terraform.tfstate`.

| Concern | How |
| --- | --- |
| Locking | Native S3 conditional writes (`use_lockfile`). Scaleway gained `If-None-Match` support in May 2026, so no DynamoDB stand-in is needed. A `.tflock` object appears beside the state while an operation runs. |
| At rest, client side | PBKDF2 → AES-GCM, `enforced` for both state and plan files. The state is ciphertext before it leaves your machine. |
| At rest, server side | `encrypt = true` additionally asks Scaleway for SSE-S3. |
| Non-AWS quirks | `skip_s3_checksum` is required: since January 2025 the AWS SDK adds CRC32 trailers to every PUT by default, which non-AWS implementations reject. |

`endpoints`/`use_path_style` are the current argument names. Scaleway's own
backend guide still shows the deprecated `endpoint` and `force_path_style`.

## The passphrase

`secrets/tofu.yaml`, sops-encrypted to the `admins` group in `.sops.yaml`.
`.envrc` decrypts it into `TF_VAR_state_passphrase` when you enter the
directory, so there is **no separate credential to hand around** — anyone who
can already edit the repo's secrets can run tofu, and anyone who cannot gets a
warning and a shell that works for everything except state operations.

Because it is committed (encrypted), the passphrase cannot be lost while the
repo and one admin key survive. That is the whole point of storing it this way
rather than in a password manager.

Recipients may be **age keys or SSH ed25519 public keys** — sops accepts an
`ssh-ed25519 …` line directly and decrypts with the matching private key from
`~/.ssh`, with no conversion step and nothing to keep in
`~/.config/sops/age`. Admins are listed that way.

To add an admin, add their public key under `admins` in `.sops.yaml`, then
re-key every file they should read:

```sh
sops updatekeys secrets/tofu.yaml
sops updatekeys secrets/s3-01.yaml
```

`updatekeys` decrypts before re-encrypting, so it only works for files you can
already read. `secrets/pcgewisinfo.yaml` is not in that list because no admin is
a recipient yet — see [`pcgewisinfo.md`](../pcgewisinfo/secrets.md).

Every root in this repo encrypts its state the same way, deliberately. Deciding
per root would mean remembering per root, and forgetting is silent — a live
credential sitting in plaintext in the bucket with nothing to warn you.

## Who can touch the state

Access is enforced at runtime by Scaleway IAM, not by sharing a credential.
Every operator has their **own** API key, so removing someone is revoking their
key — nothing shared has to be rotated.

The bucket lives in a **dedicated Scaleway Project** containing nothing else.
That is deliberate: IAM permission sets bottom out at *Project* scope, and
Object Storage is not among the products supporting resource-level conditions,
so an IAM policy alone cannot name a single bucket. Giving the state bucket its
own Project makes a Project-scoped grant effectively bucket-scoped.

Setup:

1. Create a Project, e.g. `tf-state`, and create the bucket inside it.
2. Create an IAM group, e.g. `tofu-operators`.
3. Attach a policy granting `ObjectStorageFullAccess`, scoped to that Project
   only.
4. Add each operator as a member and have them generate their own API key.

Offboarding is `scw iam api-key delete <access-key>`, or removing them from the
group, or locking the member. All take effect immediately.

Bucket policies are the other way to get per-bucket granularity, and are what
you would need if the bucket shared a Project with unrelated resources. They are
avoided here: `Deny` is inert in the current `2023-04-17` policy version, so the
rule is default-deny for anyone not explicitly named, and it is entirely
possible to lock yourself out — recovery needs Organization Owner rights or
`aws s3api delete-bucket-policy`.

**The passphrase is not part of this.** It is not an access credential: without
bucket access it opens nothing, so an ex-operator who keeps a copy gains
nothing, and it does not need rotating when someone leaves. Conversely, against
someone who copied the state *while* they had access, neither rotation nor
re-encryption helps — their copy stays readable with the old key. Encryption
guards against parties who never had access; IAM guards against ones who did.

What this model buys is that an offboarded operator can no longer **write** to
the state, and that per-operator keys make Scaleway's logs attributable — a
shared credential leaves a corrupted state untraceable.

What it does not buy, accepted deliberately: someone can copy the state before
they are offboarded. That is no different from copying passwords out of
Vaultwarden on the way out, and it is not worth contorting the design over.

Bucket versioning does not close that gap either — `ObjectStorageFullAccess`
includes deleting object versions, so versioning protects against accidents and
outsiders, not against an authorised operator acting in bad faith.

Object Lock **would**, and is a genuine option rather than an impossible one.
Retention applies per object *version*, and an apply writes a new version
rather than modifying a locked one, so state updates keep working while history
becomes undeletable. It is not enabled here because of what it costs:

- Enabling it is **irreversible** — "once object lock is enabled on a bucket, it
  cannot be disabled and versioning cannot be suspended".
- Compliance mode is the only variant that stops a malicious operator, because
  Governance mode is explicitly bypassable by anyone holding the right
  permission — which an operator with full access has. But under Compliance
  mode *no one*, including the Organization owner, can delete a version before
  its retention expires. If a credential ever lands in state by mistake, it
  cannot be purged.
- Every state version is retained until expiry, so storage grows with apply
  count.

Untested, and worth checking before enabling: `use_lockfile` creates and
deletes a `.tflock` object per operation. Standard S3 semantics turn that delete
into a delete marker, which Object Lock permits, so locking should be
unaffected — but that has not been verified against Scaleway.

## Migrating from local state

Done once. This sequence was rehearsed end to end in a scratch directory.

1. Do the Project, group and policy setup from *Who can touch the state*, then
   create the bucket named in `terraform/s3-01/backend.tf` in `nl-ams` inside that
   Project, with **versioning** on so a corrupt write is recoverable.

   Bucket names are unique **per region across all of Scaleway**, not per
   Project — the name forms the DNS label in
   `<bucket>.s3.nl-ams.scw.cloud`. A short generic name will collide with
   another customer's; if creation fails as already taken, pick something
   qualified and change the one line in `backend.tf`.
2. Export the credentials from *Credentials* above. `TF_VAR_state_passphrase`
   comes from `.envrc` already.
3. Keep a copy of the current state, which is still plaintext at this point:

   ```sh
   cp terraform/s3-01/terraform.tfstate terraform/s3-01/terraform.tfstate.pre-migration
   ```

4. Temporarily let tofu read that plaintext state. In the `encryption` block of
   `terraform/s3-01/backend.tf`, add the unencrypted method and replace the `state`
   block with a fallback:

   ```hcl
   method "unencrypted" "migrate" {}

   state {
     method = method.aes_gcm.state

     fallback {
       method = method.unencrypted.migrate
     }
   }
   ```

5. Migrate. This reads the local plaintext state and writes it encrypted to
   Scaleway; it runs no plan and touches no infrastructure:

   ```sh
   cd terraform && tofu init -migrate-state
   ```

6. Revert `backend.tf` — drop the `fallback` and the `unencrypted` method,
   restore `enforced = true` — then `tofu init` again. OpenTofu warns while the
   unencrypted fallback is present, which is your cue that this step is still
   outstanding.
7. Check `tofu state list` still reports every resource, and that the object in
   the bucket is ciphertext.
8. Delete `terraform.tfstate`, `terraform.tfstate.backup` and the
   `.pre-migration` copy. They are gitignored but still plaintext on disk.

A wrong passphrase fails closed with *"decryption failed for all provided
methods"* rather than silently producing an empty state.
