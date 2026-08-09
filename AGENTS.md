# Agent instructions

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
