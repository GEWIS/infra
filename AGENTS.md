# Agent instructions

## One source of truth, enforced by code

Never solve a consistency problem with documentation. When the same value is
needed in two places (a tenant list, a group name, a hostname), derive every
copy from one source in code, so a change in one place cannot leave another
stale. A docs page that says "remember to also update X" is a bug, not a fix.
If deriving it properly is hard, say so and design it; do not hand-copy the
value and document the duplication.

## Keep the docs in step with the code

`docs/` is not an afterthought — it is published as a site at
<https://gewis.github.io/infra/> and is how operators understand this
infrastructure. When you change how something works, update the matching page in
the same change:

- New host, service, OpenTofu root or Flux layer → add or extend its page under
  `docs/`, and add it to `nav:` in `mkdocs.yml` (the build runs `--strict`, so an
  unlisted page or a broken link fails CI).
- Changed behaviour, paths, commands, addresses or secrets → correct every page
  that describes them. Search `docs/` for the old value before you assume it is
  only in one place.
- Removed something → delete its page and its `nav:` entry.

One page per `##`-level topic; keep pages short. Cross-link between pages with
relative links (`../talos/index.md`), never absolute URLs.

## Tell the user you did this

Whenever you touch this repo, state in your reply whether the docs needed a
change and what you did about it — even when the answer is "no docs change
needed". The user relies on that line to trust the docs stay accurate.

## Verifying docs

`nix build .#docs` builds the site and fails on broken links or unlisted pages.
`mkdocs serve` (the dev shell provides it) previews locally.
