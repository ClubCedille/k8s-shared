# Alerting Grafana → Discord

Les alertes du cluster sont des **règles Grafana gérées** (pas d'Alertmanager dans
le cluster), définies dans `apps/grafana/helm/values.yaml` sous la clé
`alerting:`. Le chart Grafana les rend dans le ConfigMap `monitoring/grafana`.
Le groupe de templates, lui, est un ConfigMap Kustomize distinct monté dans le
pod (voir plus bas pourquoi) :

| Fichier provisionné | Source | Rôle |
|---|---|---|
| `contactpoints.yaml` | `helm/values.yaml` (`alerting:`) | Contact point `discord-cluster`, URL du webhook lue depuis Vault via `$DISCORD_WEBHOOK_URL` |
| `templates.yaml` | `resources/alerting/templates.yaml` | Groupe de templates `k8s-alerts` (formatage des notifications) |
| `policies.yaml` | `helm/values.yaml` (`alerting:`) | Routage et regroupement des alertes |
| `rules.yaml` | `helm/values.yaml` (`alerting:`) | Règles du dossier `Cluster` |

> Pourquoi un ConfigMap séparé ? Le chart Grafana applique la fonction Helm `tpl`
> à toutes les valeurs sous `alerting:`. Un Go template (`{{ define ... }}`)
> placé là serait évalué par Helm au lieu d'être transmis à Grafana. Le fichier
> est donc rendu brut par Kustomize et monté via `extraVolumes` /
> `extraVolumeMounts` dans `/etc/grafana/provisioning/alerting/templates.yaml`.
> Les deux références dans `contactpoints.yaml` sont échappées de la même
> manière (littéral Go template encapsulé dans une chaîne Helm) pour traverser
> `tpl` sans être évaluées.

Ces ressources sont **provisionnées par fichier** : elles ne sont pas modifiables
depuis l'UI Grafana (les changements UI sont écrasés au prochain reload). Toute
modification passe par Git.

## Format des notifications (v1)

Le template par défaut de Grafana affichait tous les labels des séries Prometheus
(`pod`, `instance`, `endpoint`, `prometheus_replica`, etc.), ce qui rendait les
messages Discord illisibles. Les templates `k8s.title` et `k8s.message` affichent
désormais uniquement :

- le résumé (`annotations.summary`) en première ligne ;
- `cluster`, `namespace`, `déploiement` / `statefulset`, et `job` / `cronjob`
  quand ces labels existent ;
- la sévérité ;
- l'heure de début (et de fin pour une alerte résolue) en **heure de Montréal**
  (`America/Toronto`), format `JJ/MM HH:MM`.

Les alertes regroupées dans une même notification sont séparées par une ligne
blanche. Le regroupement reste défini par `policies.yaml` (`alertname`,
`namespace`, `node`), avec `group_wait: 30s`, `group_interval: 5m` et
`repeat_interval: 4h`.

Rendu attendu dans Discord :

```
**A Deployment has had unavailable replicas for more than 15 minutes.**

- **cluster** `k8s-shared`
- **namespace** `default`
- **déploiement** `gdq`
- **sévérité** `warning`
- **depuis** `25/11 14:07` (Montréal)

[Voir la règle](…) · [Ignorer](…) · [Logs](…)
```

Le titre de l'embed devient `ALERTE · k8s-shared` (ou `RÉSOLUE · ...`).

> Note : le label `job` des règles actuelles est le **job de scrape Prometheus**
> (par ex. `kube-state-metrics`), pas un Job/CronJob Kubernetes. Le template ne
> l'affiche pas. Pour remonter un vrai Job/CronJob, il faut d'abord ajouter un
> label `job_name` ou `cronjob` sur la règle : le template les affiche
> automatiquement lorsqu'ils sont présents.

## Liens d'action (v2)

Chaque alerte se termine par une ligne de liens courts, sans emoji :

| Libellé | Destination | Quand |
|---|---|---|
| `[Voir le dashboard]` | `.DashboardURL` | Règle liée à un panneau Grafana |
| `[Voir la règle]` | `.GeneratorURL` | Repli si pas de dashboard (toujours disponible) |
| `[Ignorer]` | `.SilenceURL` (premier matcher seulement) | Toujours (ouvre le formulaire de silence pré-rempli, ne silence pas immédiatement) |
| `[Runbook]` | annotation `runbook_url` | Uniquement si l'annotation est posée sur la règle |
| `[Logs]` | Explore/Loki | Uniquement si `namespace`, `pod` ou `container` est présent dans les labels |

Le lien `[Logs]` ouvre Explore sur le datasource Loki avec un sélecteur LogQL
construit à partir des labels de l'alerte, par exemple
`{namespace="default",pod="gdq-7d9f6c8d4-x2abc",container="gdq"}`, et une
fenêtre allant d'une heure avant `StartsAt` jusqu'à `StartsAt` (ou `EndsAt` si
l'alerte est résolue). Les paramètres `panes` sont encodés avec `urlquery`.

> L'UID du datasource Loki (`P8E80F9AEF21F6940`) est codé en dur dans
> `k8s.logs`. Il provient de `GET /api/datasources` sur l'instance Grafana. Si le
> datasource est supprimé/recréé, le mettre à jour — sinon Explore ouvrira sans
> source de données. Une amélioration possible serait de lui donner un UID fixe
> via `datasources.yaml` (`uid: loki`) et de référencer dashboards/alertes avec
> cet UID.

## Déploiement et test

Le chart Grafana re-rend le ConfigMap via ArgoCD, mais Grafana **recharge les
fichiers de provisioning au démarrage ou via l'API admin** (le sidecar du chart
ne surveille que les dashboards). Après un merge, prévoir :

```sh
kubectl -n monitoring rollout restart deploy/grafana
```

Puis vérifier dans Grafana : **Alerting → Notification configuration →
Contact points → `discord-cluster` → Test** (un message de test apparaît dans
Discord), ou attendre la prochaine alerte réelle.

En cas d'erreur de template, les logs du pod contiennent un message
`failed to template ...` et la notification n'est pas envoyée ; le premier
réflexe est de revenir au template par défaut (`{{ template "default.message" . }}`)
le temps de corriger.

> Le `.SilenceURL` complet contient un `matcher=` par label de l'alerte : avec
> une dizaine de labels, l'URL dépasse la longueur que Discord accepte dans un
> lien Markdown et le `[Ignorer](...)` s'affiche en texte brut. Le template ne
> conserve donc que le premier matcher (`__alert_rule_uid__` sur les alertes
> réelles), ce qui suffit à cibler la règle entière.

> Piège de provisioning : Grafana détecte un groupe de templates via une regex
> `{{ define` (avec l'espace après `{{`). Écrire `{{- define` (trim à gauche)
> empêche la détection : Grafana ré-enveloppe alors tout le fichier dans un
> `define` et échoue au démarrage avec
> `alerting.notifications.templates.invalidFormat`.
