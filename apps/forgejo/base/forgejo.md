
# Creation de fichiers secrets:

1. **base/db-config**
```ini
[database]
DB_TYPE = postgres
HOST = postgresql-forgejo-rw.forgejo.svc.cluster.local:5432
NAME = forgejo
USER = DB_USER
PASSWD = "DB_PASSWORD"
```
2. **base/forgejo-pstgres.secret.yaml**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-forgejo-app
  namespace: forgejo
type: kubernetes.io/basic-auth
stringData:
  username: DB_USER
  password: "DB_PASSWORD"
```
3. **base/forgejo-user.secret.yaml**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: forgejo-admin-secret
  namespace: forgejo
type: Opaque
stringData:
  username: forgejo
  email: forgejo@lanets.ca
  password: "ADMIN_USER_PASSWORD"
```

4. **base/oidc.secret.yaml**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: forgejo-oauth-secret
type: Opaque
stringData:
  key: OIDC_CLIENTID
  secret: OIDC_SECRET
```