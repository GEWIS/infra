# Hosts

`gewis.sshUserCa.enable` sets sshd's `TrustedUserCAKeys` to
`/var/lib/ssh-user-ca/ca.pub` and keeps that file current from OpenBao's
unauthenticated `GET /v1/ssh/public_key`.

The key is fetched at runtime rather than committed, because the CA lives only in
OpenBao and a rebuild replaces it. A timer runs the `ssh-user-ca` unit one minute
after boot and every fifteen minutes after that. The unit only replaces the file
when the fetch returns 2xx **and** the body parses as a public key
(`ssh-keygen -l`); the new file is moved into place atomically. An unreachable
OpenBao, an error page or an empty response leaves the previous key, so certificates
keep working while the cluster is down.

sshd reads `TrustedUserCAKeys` on every authentication, so a changed key needs no
reload. Until the first successful fetch the file does not exist and only the
existing ways in work.

```sh
systemctl status ssh-user-ca.service ssh-user-ca.timer
ssh-keygen -l -f /var/lib/ssh-user-ca/ca.pub
```
