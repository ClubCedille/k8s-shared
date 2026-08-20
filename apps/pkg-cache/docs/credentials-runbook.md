# pkg-cache BasicAuth credentials

Every flavor in this app uses BasicAuth on its own dedicated sub-domain --
no mTLS anywhere (apt's GnuTLS client couldn't do client certs reliably,
see deployment.yaml; rather than split the fleet auth story across two
mechanisms, every other flavor uses the same BasicAuth pattern instead of
chasing mTLS support per package manager's TLS stack).

| Flavor  | Sub-domain                       | Secret                    |
|---------|-----------------------------------|----------------------------|
| apt     | `apt-cache.pkg.etsmtl.club`       | `apt-cache-htpasswd`       |
| dnf     | `dnf-cache.pkg.etsmtl.club`       | `dnf-cache-htpasswd`       |
| pacman  | `pacman-cache.pkg.etsmtl.club`    | `pacman-cache-htpasswd`    |
| pkg     | `freebsd-cache.pkg.etsmtl.club`   | `freebsd-cache-htpasswd`   |
| Nix     | `nix-cache.pkg.etsmtl.club`       | `nix-cache-htpasswd`       |

None of these Secrets are in this kustomization -- like Forgejo's
admin/OAuth secrets, they're applied manually and never committed with
real values. Each is independent (rotating one doesn't affect the others).

## Generating the htpasswd hash

nginx's `ngx_http_auth_basic_module` accepts the `apr1` crypt format,
generatable with `openssl` alone (no `htpasswd` binary needed):

```bash
PASSWORD=$(openssl rand -base64 18 | tr -d '/+=' | head -c 24)
HASH=$(openssl passwd -apr1 "$PASSWORD")
echo "fleet:$HASH"
```

Save `$PASSWORD` out-of-band (distribute via Ansible/CloudInit, see issue:
Mirror: intégration Ansible) -- only the hash goes into the cluster. Each
flavor should get its own independently-generated password, not a shared
one, even though the `fleet` username is reused everywhere.

## Applying the Secret

Replace `$NAME` with the flavor's Secret name from the table above
(`apt-cache-htpasswd`, `dnf-cache-htpasswd`, `pacman-cache-htpasswd`,
`freebsd-cache-htpasswd`, or `nix-cache-htpasswd`):

```bash
kubectl --context cedille-k8s-shared -n pkg-cache create secret generic $NAME \
  --from-literal=htpasswd="fleet:$HASH"
```

Rotate by re-running both commands and re-creating the Secret
(`kubectl delete secret $NAME` first, then `create` again) -- kubelet
propagates the updated mounted file to the running pod within a minute or
so, no pod restart needed.

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

## dnf (Fedora)

Confirmed live end-to-end (`dnf makecache` + `dnf install`) through
Contour/TLS/nginx BasicAuth/dl.fedoraproject.org. Unlike apt, dnf's
BasicAuth-in-URL works exactly as expected -- no proxy-vs-mirror
distinction to worry about, this is a plain reverse-proxy cache, not a
`http_proxy`-style forward proxy.

```
[fedora]
baseurl=https://fleet:PASSWORD@dnf-cache.pkg.etsmtl.club/pub/fedora/linux/releases/$releasever/Everything/$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$releasever-$basearch
```

Note the `/pub/fedora` prefix -- this cache proxies `dl.fedoraproject.org`
verbatim (path-for-path), it doesn't rewrite Fedora's own layout.

## pacman (Arch)

Confirmed live end-to-end (`pacman -Sy` + `pacman -S`) through
Contour/TLS/nginx BasicAuth/pacoloco. pacoloco serves repos at its own
`/repo/<name>` path, matched directly by a dedicated HTTPProxy route:

```
Server = https://fleet:PASSWORD@pacman-cache.pkg.etsmtl.club/repo/archlinux/$repo/os/$arch
```

## pkg (FreeBSD)

**Not validated with the real `pkg` client** -- this Linux-only k8s
cluster has no FreeBSD container runtime available. Validated instead
with `curl` (real `meta.conf` and a real 9.6 MiB `packagesite.pkg` bundle,
both 200, clean TLS handshake) as an approximation. This carries the same
caveat that caught out the original apt+mTLS assumption: a client library
succeeding with `curl` doesn't guarantee identical behavior in the actual
package manager. The risk is lower here than it was for apt's client-cert
case though -- BasicAuth-in-URL is a much more uniformly-implemented
mechanism across HTTP client libraries than TLS client-cert auth is.
**Validate on a real FreeBSD box (or OPNsense, which is FreeBSD-based)
before relying on this for the fleet.**

```
FreeBSD: {
  url: "pkg+https://fleet:PASSWORD@freebsd-cache.pkg.etsmtl.club/${ABI}/latest",
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg",
  enabled: yes
}
```

## Nix

Confirmed live end-to-end: a real store path (`hello` from nixpkgs) copied
exclusively through this substituter, credentials embedded in the store
URL (Nix supports `user:pass@host` in substituter URLs natively, no
proxy-vs-mirror ambiguity like apt had):

```
substituters = https://fleet:PASSWORD@nix-cache.pkg.etsmtl.club
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

`trusted-public-keys` still needs to be `cache.nixos.org`'s key, not a
key of our own -- this cache is a transparent proxy in front of
cache.nixos.org, it doesn't re-sign anything.
