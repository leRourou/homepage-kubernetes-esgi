# homepage Helm Chart

Dashboard d'infrastructure Kubernetes déployant [gethomepage.dev](https://gethomepage.dev) avec une stack d'observabilité complète, autoscaling, self-healing et sauvegardes.

## Stack déployée

| Composant | Version | Rôle |
|-----------|---------|------|
| Homepage | latest | Dashboard portail central |
| kube-prometheus-stack | 84.1.0 | Prometheus + Grafana + AlertManager |
| loki-stack | 2.10.3 | Loki (logs) + Promtail (collecte) |
| Velero | 12.0.1 | Sauvegarde Kubernetes |
| Garage | v1.0.0 | Object storage S3-compatible (backend Velero) |
| ntfy | latest | Notifications push self-hosted |

## Fonctionnalités

- **Rolling update** zéro downtime (maxUnavailable: 1, maxSurge: 1)
- **Self-healing** via startupProbe / livenessProbe / readinessProbe
- **HPA** CPU + mémoire (autoscaling/v2) avec politiques anti-flapping (2–6 réplicas)
- **PodDisruptionBudget** (minAvailable: 1)
- **PodAntiAffinity** inter-nœuds (mode `preferred` par défaut)
- **Sticky sessions** nginx (cookie)
- **Sécurité pod** : runAsNonRoot, drop ALL capabilities
- **Dashboards Grafana custom** : HPA + Self-Healing pour homepage et ntfy
- **Backup quotidien** namespace `homepage` via Velero → Garage S3 (rétention 30 jours)

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
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update
```

### 4. Télécharger les dépendances du chart

```bash
helm dependency update ./homepage-chart
```

### 5. Installer kube-prometheus-stack séparément

> **Pourquoi ?** `kube-prometheus-stack` dépasse la limite de 1 Mo des Secrets Helm lorsqu'il est
> inclus comme sous-chart. Il doit être installé comme release indépendante.

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace homepage \
  --create-namespace \
  -f ./homepage-chart/values-kube-prometheus-stack.yaml \
  --wait \
  --timeout 5m
```

### 6. Déployer le chart homepage

```bash
helm install homepage ./homepage-chart \
  --namespace homepage \
  --wait \
  --timeout 10m
```

### 7. Vérifier le déploiement

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

Ajouter dans `/etc/hosts` si nécessaire (normalement automatique avec kind + ingress-nginx) :

```
127.0.0.1  homepage.localhost grafana.localhost prometheus.localhost alertmanager.localhost ntfy.localhost garage.localhost
```

| Service | URL | Credentials |
|---------|-----|-------------|
| Homepage | http://homepage.localhost | — |
| Grafana | http://grafana.localhost | admin / adminchangeme |
| Prometheus | http://prometheus.localhost | — |
| AlertManager | http://alertmanager.localhost | — |
| ntfy | http://ntfy.localhost | — |
| Garage S3 | http://garage.localhost | voir `values.yaml` |

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

### Vérifier les dashboards Grafana

| Dashboard | URL |
|-----------|-----|
| HPA Homepage | http://grafana.localhost/d/homepage-hpa/hpa-scaling-homepage |
| Self-Healing Homepage | http://grafana.localhost/d/homepage-self-healing/self-healing-homepage |
| HPA ntfy | http://grafana.localhost/d/ntfy-hpa/hpa-scaling-ntfy |
| Self-Healing ntfy | http://grafana.localhost/d/ntfy-self-healing/self-healing-ntfy |

---

## Sauvegarde Velero

Le chart configure automatiquement une sauvegarde quotidienne (2h00 UTC) du namespace `homepage` avec rétention 30 jours, stockée dans Garage S3.

```bash
# Vérifier la configuration du backup
kubectl get backupstoragelocations -n homepage
kubectl get schedules -n homepage

# Déclencher un backup manuel
kubectl create backup homepage-manual \
  --include-namespaces=homepage \
  --storage-location=default \
  -n homepage

# Lister les backups disponibles
kubectl get backups -n homepage
```

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
| `serviceMonitor.enabled` | `true` | Scrape Prometheus via ServiceMonitor |
| `kube-prometheus-stack.enabled` | `false` | Release indépendante (voir `values-kube-prometheus-stack.yaml`) |
| `loki-stack.enabled` | `true` | Active Loki + Promtail |
| `velero.enabled` | `true` | Active Velero |
| `garage.enabled` | `true` | Active Garage S3 |

---

## Mise à jour

```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace homepage \
  -f ./homepage-chart/values-kube-prometheus-stack.yaml

helm upgrade homepage ./homepage-chart \
  --namespace homepage \
  --wait
```

## Désinstallation

```bash
helm uninstall homepage --namespace homepage
helm uninstall kube-prometheus-stack --namespace homepage
kubectl delete namespace homepage
```
