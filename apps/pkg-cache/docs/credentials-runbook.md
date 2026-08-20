# apt-cache BasicAuth credentials

The `apt-cache-htpasswd` Secret is **not** in this kustomization -- like
Forgejo's admin/OAuth secrets, it's applied manually and never committed
with real values.

## Generating the htpasswd hash

nginx's `ngx_http_auth_basic_module` accepts the `apr1` crypt format,
generatable with `openssl` alone (no `htpasswd` binary needed):

```bash
PASSWORD=$(openssl rand -base64 18 | tr -d '/+=' | head -c 24)
HASH=$(openssl passwd -apr1 "$PASSWORD")
echo "fleet:$HASH"
```

Save `$PASSWORD` out-of-band (distribute via Ansible/CloudInit alongside
the fleet client cert work, see issue: Mirror: intégration Ansible) --
only the hash goes into the cluster.

## Applying the Secret

```bash
kubectl --context cedille-k8s-shared -n pkg-cache create secret generic apt-cache-htpasswd \
  --from-literal=htpasswd="fleet:$HASH"
```

Rotate by re-running both commands and re-creating the Secret
(`kubectl delete secret apt-cache-htpasswd` first, then `create` again) --
kubelet propagates the updated mounted file to the running pod within a
minute or so, no pod restart needed.

## Fleet-side sources.list, not Acquire::http::Proxy

Confirmed live: `Acquire::http::Proxy "http://user:pass@apt-cache.pkg.etsmtl.club";`
always 401s against this nginx sidecar. apt's forward-proxy mode sends
credentials in a `Proxy-Authorization` header, which `ngx_http_auth_basic_module`
never looks at (it only checks `Authorization`, the origin-server header) --
nginx here isn't acting as an actual forward proxy, just a reverse
proxy/BasicAuth gate in front of apt-cacher-ng.

What works (confirmed live, `apt-get update` + `apt-get install`
end-to-end through Contour/TLS/nginx/apt-cacher-ng): point `sources.list`
directly at the cache with credentials in the URI, apt-cacher-ng's normal
direct-mirror addressing (`<cache-host>/<upstream-host>/<path>`):

```
Types: deb
URIs: https://fleet:PASSWORD@apt-cache.pkg.etsmtl.club/archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-backports
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: https://fleet:PASSWORD@apt-cache.pkg.etsmtl.club/security.ubuntu.com/ubuntu/
Suites: noble-security
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
```

This is what the Ansible/CloudInit integration (issue: Mirror: intégration
Ansible) needs to template into fleet machines' `sources.list`, not a proxy
config.
