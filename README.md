# homepage Helm Chart

Dashboard d'infrastructure Kubernetes déployant [gethomepage.dev](https://gethomepage.dev) avec une stack d'observabilité complète, autoscaling, self-healing et sauvegardes.

## Stack déployée

| Composant | Version | Rôle |
|-----------|---------|------|
| Homepage | latest | Dashboard portail central |
| victoria-metrics-k8s-stack | 0.75.0 | VMSingle + VMAgent + VMAlertmanager + Grafana |
| loki-stack | 2.10.3 | Loki (logs) + Promtail (collecte) |
| Velero | 12.0.1 | Sauvegarde Kubernetes |
| Velero UI | 0.14.0 | Interface web pour les backups Velero |
| Garage | v1.0.0 | Object storage S3-compatible (backend Velero) |

## Fonctionnalités

- **Rolling update** zéro downtime (maxUnavailable: 1, maxSurge: 1)
- **Self-healing** via startupProbe / livenessProbe / readinessProbe
- **HPA** CPU + mémoire (autoscaling/v2) avec politiques anti-flapping (2–6 réplicas)
- **PodDisruptionBudget** (minAvailable: 1)
- **PodAntiAffinity** inter-nœuds (mode `preferred` par défaut)
- **Sticky sessions** nginx (cookie)
- **Sécurité pod** : runAsNonRoot, drop ALL capabilities
- **Dashboards Grafana custom** : HPA, Self-Healing, Loki logs, Velero backups
- **Backup quotidien** et **horaire** du namespace `homepage` via Velero → Garage S3

---

## Prérequis

| Outil | Version minimale |
|-------|-----------------|
| Docker | 20.x+ |
| kind | 0.20+ |
| kubectl | 1.25+ |
| Helm | 3.x |

---

## Installation

### 1. Créer le cluster kind

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
    - containerPort: 80
      hostPort: 80
      protocol: TCP
    - containerPort: 443
      hostPort: 443
      protocol: TCP
  - role: worker
  - role: worker
  - role: worker
EOF
```

### 2. Installer ingress-nginx

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Attendre que l'ingress controller soit prêt
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

### 3. Ajouter les dépôts Helm

```bash
helm repo add victoria-metrics https://victoriametrics.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo add otwld https://helm.otwld.com/
helm repo update
```

### 4. Télécharger les dépendances du chart

```bash
helm dependency update ./homepage-chart
```

### 5. Déployer le chart homepage

```bash
helm install homepage ./homepage-chart \
  --namespace homepage \
  --create-namespace \
  --wait \
  --timeout 15m
```

### 6. Vérifier le déploiement

```bash
# Tous les pods doivent être Running/Ready
kubectl get pods -n homepage

# Vérifier l'HPA
kubectl get hpa -n homepage

# Vérifier les ingress
kubectl get ingress -n homepage
```

---

## Accès aux services

Ajouter dans `/etc/hosts` :

```
127.0.0.1  homepage.localhost grafana.localhost prometheus.localhost alertmanager.localhost velero-ui.localhost
```

| Service | URL | Credentials |
|---------|-----|-------------|
| Homepage | http://homepage.localhost | — |
| Grafana | http://grafana.localhost | admin / adminchangeme |
| Prometheus | http://prometheus.localhost | — |
| AlertManager | http://alertmanager.localhost | — |
| Velero UI | http://velero-ui.localhost | admin / admin |

---

## Tests

### Self-healing

Supprimer des pods brutalement et observer la récupération automatique :

```bash
# Supprimer 2 pods simultanément (un par nœud)
kubectl delete pods -n homepage -l app.kubernetes.io/name=homepage --grace-period=0

# Observer la recréation (recovery ~65 secondes)
watch kubectl get pods -n homepage
```

### Scaling HPA

Générer de la charge CPU pour déclencher le scale-up :

```bash
# Lancer une charge HTTP intensive depuis l'intérieur du cluster
kubectl run load-test --image=busybox --restart=Never -n homepage -- \
  sh -c "while true; do wget -q -O- http://homepage.homepage.svc.cluster.local:3000 > /dev/null; done"

# Observer le scale-up (2 → 6 réplicas en ~2 minutes)
watch kubectl get hpa -n homepage

# Supprimer la charge pour observer le scale-down (~5 minutes)
kubectl delete pod load-test -n homepage
```

### Test Loki (collecte des logs)

Générer du trafic HTTP pour alimenter Loki, puis vérifier la collecte depuis Grafana :

```bash
# Activer le job de test (envoie 100 requêtes à homepage)
helm upgrade homepage ./homepage-chart \
  --namespace homepage \
  --set lokiTest.enabled=true \
  --set lokiTest.requestCount=100

# Suivre l'exécution du job
kubectl logs -n homepage -l job-name=homepage-loki-test -f

# Désactiver après le test
helm upgrade homepage ./homepage-chart \
  --namespace homepage \
  --set lokiTest.enabled=false
```

Vérifier les logs dans Grafana : http://grafana.localhost/d/loki-homepage/logs-homepage-loki

### Vérifier les dashboards Grafana

| Dashboard | URL |
|-----------|-----|
| HPA Homepage | http://grafana.localhost/d/homepage-hpa/hpa-scaling-homepage |
| Self-Healing Homepage | http://grafana.localhost/d/homepage-self-healing/self-healing-homepage |
| Logs Homepage (Loki) | http://grafana.localhost/d/loki-homepage/logs-homepage-loki |
| Velero Sauvegardes | http://grafana.localhost/d/velero-backups/velero-sauvegardes-kubernetes |

---

## Sauvegarde Velero

Le chart configure automatiquement deux schedules de backup du namespace `homepage` stockés dans Garage S3 :

| Schedule | Cron | Rétention |
|----------|------|-----------|
| `homepage-daily` | `0 2 * * *` (2h00 UTC) | 30 jours |
| `homepage-hourly` | `0 * * * *` (toutes les heures) | 48 heures |

```bash
# Vérifier la configuration du backup
kubectl get backupstoragelocations -n homepage
kubectl get schedules -n homepage

# Déclencher un backup manuel
velero backup create homepage-manual \
  --include-namespaces=homepage \
  --storage-location=default \
  -n homepage

# Lister les backups disponibles
kubectl get backups -n homepage
```

L'interface web Velero UI est disponible sur http://velero-ui.localhost pour lancer et suivre les backups sans CLI.

---

## Valeurs importantes

| Clé | Défaut | Description |
|-----|--------|-------------|
| `replicaCount` | `2` | Réplicas si HPA désactivé |
| `autoscaling.enabled` | `true` | Active/désactive l'HPA |
| `autoscaling.minReplicas` | `2` | Plancher HPA |
| `autoscaling.maxReplicas` | `6` | Plafond HPA |
| `autoscaling.targetCPUUtilizationPercentage` | `70` | Seuil CPU HPA (%) |
| `autoscaling.targetMemoryUtilizationPercentage` | `80` | Seuil mémoire HPA (%) |
| `podAntiAffinity.mode` | `preferred` | `preferred` (dev) ou `required` (prod) |
| `podDisruptionBudget.enabled` | `true` | Active le PDB |
| `podDisruptionBudget.minAvailable` | `1` | Pods minimum disponibles |
| `ingress.host` | `homepage.localhost` | Hostname de l'ingress |
| `ingress.tls.enabled` | `false` | TLS via cert-manager |
| `lokiTest.enabled` | `false` | Active le job de test Loki |
| `lokiTest.requestCount` | `100` | Nombre de requêtes générées par le job |
| `victoria-metrics-k8s-stack.enabled` | `true` | Active VMSingle + Grafana + VMAlertmanager |
| `loki-stack.enabled` | `true` | Active Loki + Promtail |
| `velero.enabled` | `true` | Active Velero |
| `velero-ui.enabled` | `true` | Active l'interface web Velero UI |
| `garage.enabled` | `true` | Active Garage S3 |

---

## Mise à jour

```bash
helm upgrade homepage ./homepage-chart \
  --namespace homepage \
  --wait
```

## Désinstallation

```bash
helm uninstall homepage --namespace homepage
kubectl delete namespace homepage
```
