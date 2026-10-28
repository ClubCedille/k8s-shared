# Matomo

Matomo runs from the `digitalist/matomo` Helm chart. `/var/www/html` is an
`emptyDir` populated from the image on every pod start, so anything installed
manually into a running pod (plugins, config edits) is lost when the pod is
replaced.

## Login OIDC (Authentik)

Matomo does not bundle an OIDC login plugin. `matomo.installCommand` in
`helm/values.yaml` downloads `LoginOIDC` 5.0.0 from the Matomo Marketplace
during pod init, pins and verifies the upstream zip's SHA-256, then applies the
small compatibility patch described below before activating the plugin.

- Plugin: <https://plugins.matomo.org/LoginOIDC>
- Source: <https://github.com/dominik-th/matomo-plugin-LoginOIDC>
- Pinned download: <https://plugins.matomo.org/api/2.0/plugins/LoginOIDC/download/5.0.0>
- Pinned SHA-256: `36a87b7361547b8910a5a6f76cf434b07667ed8af0b266e38d45e107d541ab4f`

The plugin is not stored in this repository. If the marketplace is unavailable
during a pod start, init fails and Kubernetes retries it.

### Compatibility patch

The plugin's `install()` creates a foreign key from
`matomo_loginoidc_provider.user` to `matomo_user.login`. On MariaDB 11 those
tables use different collations (`utf8mb4_uca1400_ai_ci` for core Matomo tables,
`utf8mb4_general_ci` for the plugin table), so activation fails with:

```
SQLSTATE[HY000]: General error: 1005 Can't create table
`matomo`.`matomo_loginoidc_provider` (errno: 150 "Foreign key constraint is
incorrectly formed")
```

The `perl` one-liner in `installCommand` removes only that foreign key. The
plugin does not rely on `ON DELETE CASCADE` (it deletes links explicitly in
`unlink()`), so it keeps working.

### Credentials

The Authentik provider is created by `terraform/matomo/authentik-vault` and its
client id/secret are stored in Vault at
`kv/matomo/default/matomo-oidc-secret`. `prod/vault-secret.yaml` syncs them into
the `matomo` namespace as `matomo-oidc-secret`; the `matomo-init` container
mounts that secret and writes the values into `config.ini.php`.

### Account policy

`allowSignup=1` lets any Authentik user create a Matomo account (with no site
access by default), and `autoLinking=1` links an existing Matomo user when the
Authentik username matches the Matomo login. Set both to `0` in
`helm/values.yaml` if accounts should only be created/linked by an
administrator.
