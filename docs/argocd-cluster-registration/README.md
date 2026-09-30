# Registering an external cluster in ArgoCD (Omni-backed)

Runbook for adding an Omni-hosted cluster to the k8s-shared ArgoCD, or for
reviving one whose token has expired.

Written up from the `k8s-cedille-sandbox` outage of 2026-09-28, where the
cluster showed as `Failed` and every sync to it silently stalled.

---

## 1. Symptom

```console
$ argocd cluster list
SERVER                                                                     NAME                  VERSION  STATUS   MESSAGE
https://cedille.kubernetes.omni.siderolabs.io?cluster=k8s-cedille-sandbox  k8s-cedille-sandbox  v1.36.4  Failed   failed to get server version: failed to get server version: the server has asked for the client to provide credentials
```

Apps in the target AppProject stay `OutOfSync` / never sync.

## 2. Confirm it is the token, not the config

An AppProject only grants *permission* to deploy to a destination — it does not
register a cluster. So a broken cluster is never an AppProject problem. Verify
in this order.

```bash
# a. the cluster Secret exists in argocd and carries the right label
kubectl --context cedille-k8s-shared -n argocd get secrets \
  -l argocd.argoproj.io/secret-type=cluster \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.data.name | @base64d}{"\n"}{end}'

# b. decode the stored token and read its expiry
SECRET=cluster-cedille.kubernetes.omni.siderolabs.io-585688308
kubectl --context cedille-k8s-shared -n argocd get secret "$SECRET" \
  -o jsonpath='{.data.config}' | base64 -d \
  | python3 -c "
import json,sys,base64,time
c=json.load(sys.stdin); t=c['bearerToken']; p=t.split('.')
d=json.loads(base64.urlsafe_b64decode(p[1]+'='*(-len(p[1])%4)))
for k,v in d.items(): print(f'{k}: {v}')
e=d.get('exp')
print('STATE:', 'EXPIRED' if e and e<time.time() else f'valid {(e-time.time())/86400:.1f} days')
"

# c. replay the exact request ArgoCD makes
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H "Authorization: Bearer $TOK" \
  "https://cedille.kubernetes.omni.siderolabs.io?cluster=<CLUSTER>/api/v1/namespaces/default"
```

`HTTP 401` + `token has invalid claims: token is expired` = expired token.
`HTTP 200` = the token is fine and the problem is elsewhere.

If (c) returns 200 but ArgoCD still reports `Failed`, ArgoCD is serving a cached
cluster state — wait ~3 min or restart the `argocd-application-controller`.
Do not re-patch a secret that already verifies.

## 3. Why `argocd cluster add` does not work here

**Do not use `argocd cluster add` for Omni-backed clusters.** It always
provisions its own `argocd-manager` ServiceAccount and registers that SA's
static token. Omni fronts the apiserver with its own authenticating proxy that
accepts **only Omni-issued tokens**, so the token `cluster add` just created is
rejected with the exact 401 above. This was confirmed three times on
`k8s-cedille-sandbox`:

- plain `cluster add` → `Unauthenticated ... token is expired`
- `cluster add --service-account=""` → still uses `argocd-manager`
- `cluster add --upsert` → same

Two corollaries:

- There is **no durable non-expiring token** for an Omni cluster. A
  `kubernetes.io/service-account-token` Secret created inside the cluster also
  401s at Omni's proxy. The 1-year Omni SA token is the only credential that
  works, so this recurs annually by design.
- `argocd cluster add --from=<kubeconfig>` is not a flag. `--from` belongs to
  `argocd repo add`. `cluster add` takes a `CONTEXT` plus `--kubeconfig`.

## 4. Get a fresh token

An Omni service-account kubeconfig (plain `token:`, no `exec:` block) is what
you need. The user kubeconfig in `~/.kube/` is an `exec: kubectl oidc-login`
browser flow — ArgoCD pods have no `oidc-login` and no browser, so that
credential can never be used.

```bash
# check the auth mechanism before using a kubeconfig
kubectl config view --kubeconfig "$KC" --raw -o jsonpath='{.users[0].user}' \
  | python3 -c "import json,sys; print(list(json.load(sys.stdin).keys()))"
# want: ['token']        have: ['exec']  <-- unusable for ArgoCD
```

Verify it works against the canonical URL before touching anything:

```bash
TOK=$(kubectl config view --kubeconfig "$KC" --raw -o jsonpath='{.users[0].user.token}')
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H "Authorization: Bearer $TOK" \
  "https://cedille.kubernetes.omni.siderolabs.io?cluster=<CLUSTER>/api/v1/namespaces/default"
```

## 5. Patch the Secret — do not recreate it

The Secret name and `data.server` are load-bearing:

- ArgoCD matches an app's `destination.server` against the Secret's `data.server`.
- The AppProject lists the destination in
  `system/argocd/resources/argocd-projects.yaml`.
- If `server` drifts, or the Secret is recreated under a new name, every app in
  the project is rejected with "destination not permitted" — and the old Secret
  lingers, so the setup half-works and is very confusing to debug.

**Patch `data.config` only.** That leaves the name and `data.server` untouched,
so the AppProject destination keeps matching by construction.

```bash
SECRET=cluster-cedille.kubernetes.omni.siderolabs.io-585688308   # from step 2a
TOK=$(kubectl config view --kubeconfig "$KC" --raw -o jsonpath='{.users[0].user.token}')

PATCH=$(jq -Rn --arg t "$TOK" \
  '{data:{config:({bearerToken:$t,tlsClientConfig:{insecure:false}}|tojson|@base64)}}')

kubectl --context cedille-k8s-shared -n argocd patch secret "$SECRET" \
  --type=merge -p "$PATCH"
```

Expect `secret/... patched`. The first run triggers a browser OIDC login against
k8s-shared.

### jq gotcha that cost real time

This is correct:

```bash
'{data:{config:({bearerToken:$t,tlsClientConfig:{insecure:false}}|tojson|@base64)}}'
```

This fails with `unexpected INVALID_CHARACTER at column 16`:

```bash
'{data:{config:(@{bearerToken:$t,tlsClientConfig:{insecure:false}}|tojson|@base64)}}'
```

`@` is jq's *format* operator (as in `@base64`), so `(@{...})` cannot lead an
expression. `@base64` has to wrap the finished object, not precede it. Always
smoke-test the patch with a dummy token first:

```bash
echo '{}' | jq -Rn '{data:{config:({bearerToken:"TESTTOKEN",tlsClientConfig:{insecure:false}}|tojson|@base64)}}' \
  | jq -r '.data.config' | base64 -d
# expect: {"bearerToken":"TESTTOKEN","tlsClientConfig":{"insecure":false}}
```

### The canonical `server` URL

Omni kubeconfigs hand you `https://cedille.kubernetes.na-west-1.omni.siderolabs.io`
— different hostname, no `?cluster=`. The AppProject expects:

```
https://cedille.kubernetes.omni.siderolabs.io?cluster=<CLUSTER>
```

Both resolve to the same IP and both accept the token, but only the second
string matches the project destination. Never let the kubeconfig's raw `server`
value reach the Secret.

## 6. Registering a brand-new cluster (no Secret yet)

If step 2a shows no Secret for the cluster, create one. Same three data keys,
plus the label ArgoCD requires:

```bash
CLUSTER=<CLUSTER>
SERVER="https://cedille.kubernetes.omni.siderolabs.io?cluster=${CLUSTER}"
CFG=$(jq -Rn --arg t "$TOK" \
  '{bearerToken:$t,tlsClientConfig:{insecure:false}}' | base64 -w0)

kubectl --context cedille-k8s-shared -n argocd create secret generic \
  "cluster-cedille.kubernetes.omni.siderolabs.io-<hash>" \
  --type=Opaque \
  --from-literal="config=${CFG}" \
  --from-literal="name=${CLUSTER}" \
  --from-literal="server=${SERVER}" \
  --from-literal="namespace=*" \
  --dry-run=client -o yaml \
| kubectl label --local -f - 'argocd.argoproj.io/secret-type=cluster' -o yaml \
| kubectl --context cedille-k8s-shared -n argocd apply -f -
```

`kubectl create secret generic` has no `--label` flag — pipe through
`kubectl label --local` to attach the label ArgoCD requires. Without
`argocd.argoproj.io/secret-type: cluster` the Secret is ignored entirely and
`argocd cluster list` stays empty.

The trailing `<hash>` is cosmetic — ArgoCD reads the `name` key. Match the
existing convention (`cluster-<host>-<hash>`) so the Secret sorts next to its
siblings, but do not invent a different host prefix.

Then add the AppProject stanza in `system/argocd/resources/argocd-projects.yaml`
with `destinations[].server` set to `$SERVER` exactly, and redeploy that
Application. ArgoCD reads the Secret directly; the project grants permission.

**The Secret is deliberately not committed** — it holds a live cluster-admin
token. It is also *not* in `resources:` in `system/argocd/kustomization.yaml`
and is gitignored by the `*secret.yaml` rule, so ArgoCD will not prune it.

## 7. Verify

```bash
kubectl --context cedille-k8s-shared -n argocd get secret "$SECRET" \
  -o jsonpath='{.data.config}' | base64 -d \
  | python3 -c "import json,sys,base64,time; \
t=json.load(sys.stdin)['bearerToken']; p=t.split('.'); \
d=json.loads(base64.urlsafe_b64decode(p[1]+'='*(-len(p[1])%4))); \
print('sub:', d['sub'], '| days left:', round((d['exp']-time.time())/86400,1))"

# independent check — do not trust ArgoCD's own status alone
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H "Authorization: Bearer $TOK" "$SERVER/api/v1/namespaces/default"

argocd login argocd.etsmtl.club    # if the CLI session is stale
argocd cluster list
```

`HTTP 200` from the raw curl is the authoritative signal.

## 8. Clean up

`argocd cluster add` leaves four unusable objects in the target cluster even
when it fails. They are dead weight — Omni's proxy rejects their token:

```
ServiceAccount/argocd-manager              (kube-system)
ClusterRole/argocd-manager-role
ClusterRoleBinding/argocd-manager-role-binding
Secret/argocd-manager-long-lived-token     (kube-system)
```

Remove with the static-token kubeconfig:

```bash
KC=$HOME/Code/Cedille/k8s-base/kubeconfig
kubectl --kubeconfig "$KC" -n kube-system delete secret argocd-manager-long-lived-token
kubectl --kubeconfig "$KC" -n kube-system delete sa argocd-manager
kubectl --kubeconfig "$KC" delete clusterrolebinding argocd-manager-role-binding
kubectl --kubeconfig "$KC" delete clusterrole argocd-manager-role
```

Also delete any scratch kubeconfig you copied out, and the stale
`system/argocd/cluster-secret.yaml` if present — it is a gitignored leftover
pointing at a *different* cluster and will mislead the next person.

## 9. Before you finish: rotate what you pasted

While diagnosing, an Omni service-account private key was pasted into a chat
session in plaintext and written to `/tmp/opencode/`. Treat it as compromised:

```bash
shred -u /tmp/opencode/sa-key.asc \
          /tmp/opencode/sa-key.clean.asc \
          /tmp/opencode/sa-key.short.asc \
          /tmp/opencode/mgr-token \
          /tmp/opencode/sa-kubeconfig.yaml
rm -f ~/.talos/keys/sa-argocd-*.pgp       # only if the sa-argocd omnictl context is unused
```

Then regenerate the key in the Omni UI. Note the pasted key is **not** an Omni
API credential — it is an OpenPGP key used by SideroV1 auth, and the tokens it
mints are what grant access. Rotating it requires re-exporting from Omni.

Never paste a private key into a chat or a command line that gets logged. Write
it to a `chmod 600` file from your own terminal and reference the path.

## 10. Recurrence

These tokens carry a **365-day** TTL and nothing monitors them. The failure is
silent until the day they lapse. Put a calendar reminder at ~330 days, or
better, script steps 4–7 and run them on a schedule. `k8s-poc` and the
production-v2 cluster use the same Omni-SA pattern and have the same cliff.

Because the token is `groups: ["system:masters"]` (cluster-admin), narrowing it
means moving off the Omni SA model entirely — which Omni's proxy currently does
not allow. Treat cluster-admin parity as the accepted cost, and limit the blast
radius with AppProject destination scoping instead.