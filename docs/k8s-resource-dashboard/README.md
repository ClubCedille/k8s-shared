# Recensement des ressources Kubernetes & détection OOM

Dashboard Grafana : **Kubernetes → Ressources, gaspillage & risques OOM**
(uid `k8s-resources-oom-risk`, fichier
`apps/grafana/resources/dashboards/k8s-resources-oom-risk.yaml`).

## Contexte

Le besoin initial était double :

1. identifier les services victimes de **OOM kills** ;
2. identifier les services dont les **requests sont disproportionnées** par
   rapport à l'usage réel (et, à l'inverse, les plus stressés).

Un dashboard Grafana a été retenu plutôt qu'un script ponctuel afin de pouvoir
rejouer l'analyse sur n'importe quelle période et trier les résultats.

## Prérequis de collecte (important)

Avant ce changement, **aucune** des métriques nécessaires n'existait dans
Mimir. Vérification faite le 2026-11-19 :

```promql
count(kube_pod_container_resource_requests)                 # vide
count(kube_pod_container_resource_limits)                   # vide
count(container_memory_working_set_bytes)                   # vide
count(container_cpu_usage_seconds_total)                    # vide
count(container_oom_events_total)                            # vide
```

Cause : `apps/prometheus/helm/values.yaml` désactivait `kubeStateMetrics` et
`kubelet` (scrape cAdvisor), et le ServiceMonitor de `metrics-server` est
également désactivé. `metrics-server` ne expose d'ailleurs pas l'usage des
conteneurs sous forme de séries Prometheus : il ne sert que l'API
`metrics.k8s.io`. Le Prometheus externe de `monitoring01` n'émet pas ces
métriques K8s non plus.

Le dashboard seul aurait donc été vide. Deux collectes ont été activées dans
`apps/prometheus/helm/values.yaml` :

- **kube-state-metrics** : `kube_pod_container_resource_requests` /
  `kube_pod_container_resource_limits` (requests/limits), état des pods ;
- **kubelet `/metrics/cadvisor`** via `kubelet.enabled: true` :
  `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes`,
  `container_oom_events_total`.

Le scrape cAdvisor est limité au strict nécessaire (endpoint cAdvisor seul,
intervalle 30s aligné sur `scrapeInterval`) pour contenir la cardinalité
envoyée à Mimir. Le `tlsConfig.insecureSkipVerify: true` de KPS est attendu ici
(certificats serving Talos signés par une CA par nœud — même raison que
`--kubelet-insecure-tls` dans `apps/metrics-server`). Le ClusterRole du
Prometheus possède déjà `nodes/metrics`.

> **Conséquence : pas de rétroactivité.** Les données commencent au sync
> ArgoCD de `apps/prometheus`. Le dashboard reste vide pour les périodes
> antérieures ; prévoir 24-48 h d'historique avant de tirer des conclusions.

## Vérification après synchronisation

```bash
# 1. Collecteurs en place
kubectl get pods -n monitoring | grep kube-state-metrics
kubectl get servicemonitor -n kube-system    # servicemonitor kubelet (cAdvisor)

# 2. Métriques effectivement remontées dans Mimir
kubectl port-forward -n monitoring svc/mimir-query-frontend 18080:8080 &
for m in kube_pod_container_resource_requests \
         container_memory_working_set_bytes \
         container_oom_events_total; do
  curl -s "http://localhost:18080/prometheus/api/v1/query?query=count(${m}{cluster=\"k8s-shared\"})"
done

# 3. Vérifier que la jointure KSM <-> cAdvisor produit bien des lignes
#    (remplacer 7d par la période voulue)
```

La jointure se fait sur `namespace`, `pod`, `container` (la clé affichée est
`namespace / pod / container`). Le label `node` n'est pas utilisé : les séries
cAdvisor ne le portent pas par défaut, contrairement à celles de
kube-state-metrics.

Piège rencontré lors de la construction du dashboard : bien que
`externalLabels.prometheus: in-cluster` soit positionné dans `values.yaml`,
prometheus-operator **écrase** ce label par `prometheus="<namespace>/<name>"`
(`prometheusExternalLabelName` est prioritaire sur `externalLabels`). Vérifié
sur les séries déjà présentes dans Mimir :

```promql
up{cluster="k8s-shared"}   # prometheus="monitoring/prometheus-kube-prometheus-prometheus"
```

Les requêtes du dashboard filtrent donc uniquement sur `cluster="k8s-shared"`,
ce qui distingue correctement ces séries de celles remote-writées par
`monitoring01` (`cluster="etsmtl"`). Ne pas ajouter de filtre
`prometheus="in-cluster"` : il ne retournerait rien.

## Lecture des colonnes du tableau principal

| Colonne | Source | Interprétation |
|---|---|---|
| CPU req / limite | `kube_pod_container_resource_{requests,limits}{resource="cpu"}` | Demande / plafond ordonnanceur, en cores |
| CPU moy. | `rate(container_cpu_usage_seconds_total[$window])` | Moyenne sur la période `$window` |
| CPU req/use `(x)` | req ÷ max(usage, 0.001) | **Gaspillage** CPU : 10 = on demande 10× ce qu'on consomme |
| CPU % limite | usage ÷ limite | Stress CPU ; rouge au-delà de 95 % |
| RAM req / limite / moy. / pic | KSM + `avg_over_time` / `max_over_time(working_set)` | En bytes (MiB/GiB) |
| RAM req/use `(x)` | req ÷ max(usage, 1) | **Gaspillage** mémoire |
| RAM % limite, RAM pic % limite | moyenne/pic ÷ limite | **Risque OOM** : un pic proche de 100 % précède souvent le kill |
| OOM kills | `increase(container_oom_events_total[$window])` | Nombre d'événements OOM sur la période |

Le tableau est triable en cliquant sur un en-tête. Tri par défaut : `OOM kills`
décroissant. Deux barres latérales donnent le top 10 OOM et le top 10
sur-provisionnement mémoire ; deux graphiques montrent l'évolution agrégée
requests / limits / usage.

Variables : `Période d'analyse` (`$window` : 1h, 6h, 24h, 7d, 30d — défaut
7d), `Namespace` (multi), `Filtre pod` (regex). Les graphiques agrégés utilisent
la plage de temps du dashboard, indépendamment de `$window`.

### Limites d'interprétation

- `container_oom_events_total` compte les événements observés par cAdvisor.
  Un conteneur tué puis supprimé peut voir son compteur disparaître avec la
  série ; croiser avec les redémarrages dans `kubectl describe pod` si besoin.
- La mémoire utilisée est le *working set* (y compris page cache actif), pas la
  RSS seule : c'est la métrique utilisée par le kubelet pour l'OOM kill, donc
  la bonne pour ce diagnostic.
- Un `req/use` élevé n'est pas toujours un gaspillage ( pics courts,
  réservation pour une HPA, burst de démarrage). Le `pic % limite` permet de
  distinguer les deux cas.
- Les conteneurs `container=""` (sandbox pause) sont exclus. Les pods
  terminés hors de la période ne remontent pas dans la jointure KSM.

## Coût et alternatives

- Volume ajouté estimé : ~1 série de requests + 1 de limits par conteneur
  (KSM, 30s) et ~3 séries cAdvisor par conteneur (CPU, working set, OOM, 30s).
  Sur ce cluster, c'est de l'ordre de quelques milliers de séries. Si
  l'impact Mimir devient problématique, augmenter `cAdvisorInterval` ou
  restreindre `cAdvisorMetricRelabelings` dans `values.yaml`.
- Si la collecte ne peut pas être activée, un script `kubectl` + API
  `metrics.k8s.io` peut produire un rapport ponctuel (requests/limits + usage
  instantané + `lastState.terminated.reason == OOMKilled`), mais sans
  historique ni ratios sur période — d'où le choix du dashboard.

## Fichiers modifiés

- `apps/prometheus/helm/values.yaml` : activation KSM + scrape cAdvisor.
- `apps/grafana/resources/dashboards/k8s-resources-oom-risk.yaml` : dashboard.
- `apps/grafana/kustomization.yaml` : enregistrement du ConfigMap.
