# planifets-chatbot

Les manifests sont la source de vérité pour la configuration de Qdrant et de llama-server.

## Fonctionnement du cluster Qdrant

Chaque environnement possède son propre cluster Qdrant de **trois pairs**, pas trois bases indépendantes.

- Le pair `planifets-chatbot-qdrant-0` initialise le cluster. Les deux autres le rejoignent via son adresse DNS stable et le protocole inter-pairs.
- Le service headless fournit les adresses des pairs. Un pair qui reçoit une requête peut contacter les autres pour accéder aux shards nécessaires.
- Chaque pair conserve ses données sur son propre PVC. Le stockage persistant permet de retrouver son état après un redémarrage ; il ne remplace pas la réplication Qdrant.
- L'anti-affinité répartit les pairs sur des nœuds Kubernetes distincts. Le budget de perturbation limite les interruptions volontaires à un pair à la fois.

### Réplication et disponibilité

Le consensus du cluster repose sur une majorité : deux pairs sur trois doivent rester disponibles pour les opérations de consensus.
La disponibilité des données dépend aussi des répliques des shards et des paramètres de cohérence de chaque collection.
Trois pods ne garantissent donc pas, à eux seuls, trois copies de chaque vecteur.

Lors de la création ou de la reprise d'une collection, vérifier son facteur de réplication et la répartition effective de ses shards.
Une modification du facteur par défaut ne reconfigure pas automatiquement les collections existantes.

Ne pas supprimer les PVC pour résoudre un problème de quorum : préserver les données et diagnostiquer les pairs avant toute reconstruction.

[Documentation Qdrant : déploiement distribué](https://qdrant.tech/documentation/scaling/distributed_deployment/)
