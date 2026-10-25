# Homepage sur Kubernetes

Chart Helm qui déploie le tableau de bord [Homepage](https://gethomepage.dev) sur un cluster Kubernetes local (kind).

Le déploiement vise la haute disponibilité et comprend une stack complète d'observabilité (métriques, logs, alertes) et de sauvegarde. Projet réalisé dans le cadre du cursus DevOps de l'ESGI.

## Fonctionnalités

- Rolling update sans interruption de service (`maxUnavailable: 1`, `maxSurge: 1`).
- Auto-réparation via les sondes `startup`, `liveness` et `readiness`.
- Autoscaling horizontal (HPA `autoscaling/v2`) sur le CPU et la mémoire, de 2 à 6 réplicas, avec une politique anti-oscillation.
- PodDisruptionBudget et anti-affinité entre nœuds.
- Sessions persistantes par cookie sur l'ingress nginx.
- Pods durcis : exécution sans root, toutes les capabilities retirées.
- Tableaux de bord Grafana versionnés dans le dépôt : HPA, auto-réparation, logs Loki, ressources du cluster.
- Sauvegarde du namespace toutes les heures (conservée 48 h) et tous les jours (conservée 30 jours).

## Choix techniques

| Besoin | Choix | Raison |
|---|---|---|
| Packaging | Helm, avec les composants en sous-charts | Un seul `helm install` déploie toute la stack ; les versions sont figées dans `Chart.lock` |
| Cluster local | kind (1 control plane, 3 workers) | Plusieurs nœuds pour tester l'anti-affinité et la tolérance aux pannes |
| Métriques | VictoriaMetrics k8s stack | Compatible Prometheus et plus économe en ressources ; Grafana et Alertmanager sont inclus |
| Logs | Loki et Promtail | Indexation des labels seulement, intégration native dans Grafana |
| Autoscaling | metrics-server | Source des métriques CPU et mémoire pour le HPA |
| Sauvegarde | Velero et Velero UI | Sauvegarde des ressources Kubernetes et des volumes, planifiée par cron |
| Stockage S3 | Garage | Stockage objet compatible S3, léger et auto-hébergé ; il sert de backend à Velero |

## Architecture

```
                    ingress-nginx (*.localhost)
                              |
        +---------------------+----------------------+
        |                     |                      |
   Homepage (2-6 pods)     Grafana            Velero UI
   HPA, PDB, sondes           |                      |
        |              VictoriaMetrics          Velero ---> Garage (S3)
        |              (VMSingle, VMAgent,
        |               Alertmanager)
        |                     ^
   Promtail ---> Loki --------+   metrics-server ---> HPA
```

```
Chart.yaml            Dépendances (sous-charts) et versions
values.yaml           Configuration de l'application et des sous-charts
templates/            Homepage (deployment, service, ingress, HPA, PDB), Garage, tableaux de bord Grafana, job de test Loki
dashboards/           Tableaux de bord Grafana au format JSON, chargés automatiquement
scripts/              Tests de panne et de charge
Makefile              Installation, mise à jour, lint
```

## Installation

Prérequis : Docker, kind 0.20 ou supérieur, kubectl 1.25 ou supérieur, Helm 3, Python 3 avec PyYAML (utilisé par `make install`).

1. Créer le cluster :

```bash
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
    - |
      kind: InitConfiguration
      nodeRegistration:
        kubeletExtraArgs:
          node-labels: "ingress-ready=true"
    extraPortMappings:
    - { containerPort: 80, hostPort: 80, protocol: TCP }
    - { containerPort: 443, hostPort: 443, protocol: TCP }
  - role: worker
  - role: worker
  - role: worker
EOF
```

2. Installer l'ingress controller :

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait -n ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=90s
```

3. Ajouter les dépôts Helm et déployer :

```bash
helm repo add victoria-metrics https://victoriametrics.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo add otwld https://helm.otwld.com/
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

make install
```

`make install` applique d'abord les CRD des sous-charts, puis installe la release `homepage` dans le namespace `homepage`.

4. Ajouter les noms d'hôte dans `/etc/hosts` :

```
127.0.0.1  homepage.localhost grafana.localhost prometheus.localhost alertmanager.localhost velero-ui.localhost
```

| Service | URL |
|---|---|
| Homepage | http://homepage.localhost |
| Grafana | http://grafana.localhost |
| Prometheus (VictoriaMetrics) | http://prometheus.localhost |
| Alertmanager | http://alertmanager.localhost |
| Velero UI | http://velero-ui.localhost |

Les identifiants par défaut sont définis dans `values.yaml` et doivent être changés hors environnement local.

## Vérification

```bash
kubectl get pods,hpa,pdb,ingress -n homepage
kubectl get schedules,backupstoragelocations -n homepage
```

| Test | Commande | Résultat attendu |
|---|---|---|
| Auto-réparation | `scripts/kill-pod.sh` | Le pod supprimé est recréé en moins de 60 secondes |
| Montée en charge | `scripts/stress-test.sh` (nécessite `hey` ou `ab`) | Le HPA monte jusqu'à 6 réplicas pendant 2 minutes de charge |
| Remise à zéro | `scripts/reset-replicas.sh` | Le déploiement revient à 2 réplicas |
| Collecte des logs | `helm upgrade homepage . -n homepage --reuse-values --set lokiTest.enabled=true` | Requêtes visibles dans le tableau de bord Loki |

## Configuration

| Clé | Défaut | Description |
|---|---|---|
| `autoscaling.minReplicas` / `maxReplicas` | `2` / `6` | Bornes du HPA |
| `autoscaling.targetCPUUtilizationPercentage` | `70` | Seuil CPU (%) |
| `podAntiAffinity.mode` | `preferred` | `required` pour imposer un pod par nœud |
| `ingress.host` | `homepage.localhost` | Nom d'hôte de Homepage |
| `<sous-chart>.enabled` | `true` | Active ou désactive un composant (Loki, Velero, Garage, etc.) |

Commandes utiles : `make upgrade`, `make lint`, `make uninstall`.
