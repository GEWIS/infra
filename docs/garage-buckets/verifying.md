# Verifying

The interesting test is the negative one; the happy path proves very little.

```sh
bao kv get garage/observability/loki

kubectl -n observability create token garage \
  | bao write auth/kubernetes/login role=garage-observability jwt=-

kubectl -n default create token default \
  | bao write auth/kubernetes/login role=garage-observability jwt=-   # must fail
```

The second login must be refused: the role binds one namespace, and a token from
anywhere else has no way in. With a valid `garage-observability` token, reading
`garage/data/<other-namespace>/…` must return 403.

End to end, from a pod holding the synced Secret:

```sh
aws --endpoint-url http://10.82.50.100:3900 s3 ls s3://loki
```
