# Notes

- **The provider is young.** `vhco-pro/garage` is v0.1.x with one maintainer, and
  the OpenTofu registry holds no GPG key for it, so `tofu init` skips signature
  validation and only the checksums in `.terraform.lock.hcl` pin it. It is chosen
  because it is one of two that speak Admin API v2, which Garage 2.x requires.
  Its three resources map 1:1 onto `CreateBucket`, `CreateKey` and
  `AllowBucketKey`, so swapping providers later is mechanical.
- **One bucket per component is a simplification.** Mimir's docs recommend
  separate buckets for blocks, ruler and alertmanager rather than sharing one
  with prefixes. Loki and Tempo are fine on a single bucket each. Splitting Mimir
  later is three more map entries.
- **`replication_factor = 1`.** Every object has exactly one copy on one VM on
  one storage repository. Nothing in these buckets is backed up by being here.
