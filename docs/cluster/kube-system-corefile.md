# The kube-system Corefile is ours now

`flux/config/coredns/corefile.yaml` is a verbatim copy of the Corefile Talos
generates, with the `forward` replaced by two stanzas:

```
forward . 10.96.0.53 /etc/resolv.conf {
   policy sequential
   next SERVFAIL REFUSED
}
forward . /etc/resolv.conf
```

The resolver first, campus DNS behind it. Sequential means the resolver is used
whenever it is healthy; `max_fails` defaults to 2 and retires an upstream once it
has failed *more* than that, after which *forward* moves down the list.

**Two different failures need two different mechanisms, and this is easy to get
wrong.** Walking the upstream list only happens on a network error. A resolver
that is up but answering SERVFAIL — its own upstream filtered, say — is a
*successful* exchange, so the SERVFAIL is written straight to the client and
`/etc/resolv.conf` is never tried. `next` is what covers that: on a matching
RCODE it hands the query to the following plugin, which must itself be a
*forward*, hence the second stanza.

| Failure | Covered by | Measured |
| --- | --- | --- |
| DaemonSet gone (dead socket) | in-list `/etc/resolv.conf` | 3 queries at ~2s, then ~20ms, none lost |
| resolver up, answering SERVFAIL | `next` → second stanza | `NOERROR` via campus DNS in 14ms |

Without the second stanza the SERVFAIL case returns `rc2` to every pod. Verified
both ways against the real Corefile.

`next` is the right tool here and `failover` is not: `failover` retries within the
same list, and when *every* upstream returns the RCODE its loop resets its counter
at the end of the list and spins until the 5s deadline. `next` is a single hop.
Adding it costs nothing on the dead-socket path — latency is identical to the
single-stanza version.

Owning that ConfigMap is safe because **Talos applies bootstrap manifests exactly
once**. Its `ManifestApplyController` keeps an inventory and skips any object that
already exists, so it will not fight Flux — and Flux applies server-side with
`ForceOwnership`, so it takes the `Corefile` field from Talos's field manager
without a conflict. On a cold rebuild Talos creates the default first and Flux
overwrites it seconds later.

Two consequences follow from that, and both bite:

- **Deleting the file deletes cluster DNS config.** The `config` layer prunes,
  and Talos will not put the ConfigMap back.
- **A Talos upgrade will not update it.** If Sidero changes the default Corefile,
  diff against `k8stemplates.CoreDNSConfigMap` and re-vendor by hand.

CoreDNS's `reload` plugin picks the change up within ~30s, so nothing has to be
restarted.
