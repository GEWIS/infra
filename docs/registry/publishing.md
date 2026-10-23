# GitHub Actions publish with their own token

zot trusts GitHub's OIDC issuer, `https://token.actions.githubusercontent.com`,
for the audience `https://registry.gewis.nl`. No registry secret is stored in
GitHub: a job with `id-token: write` requests a token for that audience and
uses it as the password of `docker login registry.gewis.nl`, with any username.
Every token must pass these checks before zot accepts it at all:

| Check | Effect |
| --- | --- |
| `repository_owner_id == '1815510'` | only repositories of the `GEWIS` organisation; the ID survives renames |
| `ref` is `refs/heads/main`, `master`, `develop` or `refs/tags/v*` | other branches are refused |
| `event_name` is `push`, `release` or `workflow_dispatch` | pull requests are refused, including `pull_request_target`, `workflow_run` and `issue_comment`, which run with the base branch's `ref` |
| user = lowercased `owner/repo` | the identity that `publishers.yaml` grants push to |
| group `github-develop` when `ref` is `refs/heads/develop` | limits the push to the `develop` tag, see below |

A token that passes can read every image, like any logged-in identity.

## Who may push where

`flux/50_apps/zot/publishers.yaml` lists trusted publishers in the style of
[crates.io](https://crates.io/docs/trusted-publishing). Each entry under
`publishers:` names a repository, the workflow file in it that may publish, an
optional GitHub environment, and the image paths it may push to:

```yaml
- repository: gewis/<repo>          # lowercase owner/repo
  workflow: release.yml             # .github/workflows/<file>, exact name
  environment: production           # optional: the token's job must run in it
  paths:
    - <app>/<image>
    - <app>/<other-image>
```

| Rule | Effect |
| --- | --- |
| `workflow` | matched on the token's `workflow_ref`, the workflow the run started from; for a run that calls a reusable workflow, that is the caller |
| `environment` | only tokens from a job that runs in this environment, so its protection rules gate every push; the job that requests the token must declare it, which a job calling a reusable workflow cannot |
| `paths` | `read`, `create` and `update`: tags such as `:main` can move, nothing can be deleted |
| a `develop` token | may push only the tag `develop`; blobs and pushes by digest carry no tag and pass |

A repository with two publishing workflows gets two entries, and several
entries may list the same path. A token from the right repository but another
workflow or environment still passes the checks above, so it can pull, but it
cannot push.

A path under an app from [app access](../cluster/app-access.md) is
`<app>/<image>` with an image name of three or more characters, longer than
`<app>/**`: zot applies only the longest matching pattern, and the chart refuses
a path `<app>/**` would shadow, see [The config](config.md). Image names are
lowercase.
