# Test versus production

The current cluster is a test bed — three nodes with a ~10 GiB Longhorn data disk
each. The production cluster is sized far larger, so the disk-pressure and
per-node footprint concerns of running two HA engines plus the LGTM stack do not
carry over. The design above is written for production; on the test cluster, size
PVCs down accordingly.
