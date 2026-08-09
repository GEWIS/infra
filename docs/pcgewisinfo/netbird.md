# NetBird

The client attribute is `netbird`, not the `gewis` default used by `s3-01`. That
name determines the systemd unit, the `nb-netbird` interface and the
`/var/lib/netbird` state directory, so changing it would make the host register
as a **new peer** and lose its mesh address. It is pinned for that reason.
