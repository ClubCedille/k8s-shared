Le nom de domaine prévu est :

**`littlelink.etsmtl.club`**

l’application est servie comme un site statique via **NGINX** dans Kubernetes.

J'ai testé déployed le namespace via Helm et tout fonctionne. J'ai supprimé ensuite le namespace apres l'avoir testé.

# Sequence des commandes du test et deploy:
- kubectl create namespace littlelink
- helm upgrade --install littlelink .\apps\littlelink\helm -n littlelink --create-namespace
- kubectl get pods -n littlelink -w
- kubectl port-forward -n littlelink svc/littlelink 8080:80

# Suppression du namespace:
- helm uninstall littlelink -n littlelink
- kubectl delete namespace littlelink

## Structure du dossier : Généré avec le plugin ASCII Tree Generator

```text
littlelink
├── helm
│   ├── templates
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── Chart.yaml
│   └── values.yaml
├── resources
│   ├── certificate.yaml
│   └── httpproxy.yaml
└── littlelink.argoapp.yaml

```markdown
## Sécurisation de l’image Docker LittleLink

L’image Docker de LittleLink a du avoir une légère modification et se trouve dans le repo suivant (il est forked depuis l'original)

`https://github.com/Meddad-Red/littlelink`

Le `Dockerfile` a été modifié pour éviter de déployer l’application en **root**.

### Pourquoi ?

Au début, le conteneur tournait avec `uid=0(root)`, ce qui n’est pas une bonne pratique dans un cluster partagé.

Après correction :

- le conteneur tourne maintenant avec un non-privileged user ;
- l'image est maintenant basée sur une version **NGINX non-root** ;
- un listener du conteneur sur le port **8080** ;
- l’ajout d’un `securityContext` dans le `Deployment`.
```
# Vous pouvez verifier que ca ne tourne plus en non-root via la cmd suivante:
- kubectl exec -n littlelink deploy/littlelink -- id