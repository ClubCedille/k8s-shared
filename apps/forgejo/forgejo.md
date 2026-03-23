
# Creation de fichiers secrets:

1. **db-config**
```ini
DB_TYPE = postgres
HOST = postgresql-forgejo-rw.forgejo.svc.cluster.local:5432
NAME = forgejo
USER = DB_USER
PASSWD = "DB_PASSWORD"
```
create the secret using: `kubectl create secret generic forgejo-db-config --from-file=database=db-config`
2. **forgejo-pstgres.secret**
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
3. **forgejo-user.secret**
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

4. **oidc.secret**
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