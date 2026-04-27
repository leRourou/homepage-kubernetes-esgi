# homepage — Infrastructure Dashboard Kubernetes

Dashboard d'infrastructure Kubernetes déployant [gethomepage.dev](https://gethomepage.dev) avec une stack d'observabilité complète, autoscaling, self-healing et sauvegardes.

## Stack déployée

| Composant | Version | Rôle |
|-----------|---------|------|
| Homepage | latest | Dashboard portail central |
| kube-prometheus-stack | 84.1.0 | Prometheus + Grafana + AlertManager |
| loki-stack | 2.10.3 | Loki (logs) + Promtail (collecte) |
| Velero | 12.0.1 | Sauvegarde Kubernetes |
| Garage | v1.0.0 | Object storage S3-compatible (backend Velero) |

## Fonctionnalités

- **Rolling update** zéro downtime (maxUnavailable: 1, maxSurge: 1)
- **Self-healing** via startupProbe / livenessProbe / readinessProbe
- **HPA** CPU + mémoire (autoscaling/v2) avec politiques anti-flapping (2–6 réplicas)
- **PodDisruptionBudget** (minAvailable: 1)
- **PodAntiAffinity** inter-nœuds (mode `preferred` par défaut)
- **Sticky sessions** nginx (cookie)
- **Sécurité pod** : runAsNonRoot, drop ALL capabilities
- **Dashboards Grafana custom** : HPA + Self-Healing pour homepage
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

## Déploiement — une seule commande

```bash
./deploy.sh
```

Le script orchestre automatiquement (dans l'ordre) :

1. Création du cluster kind (1 control-plane + 3 workers)
2. Installation d'ingress-nginx
3. Installation de metrics-server (requis pour HPA CPU/RAM)
4. Ajout des dépôts Helm
5. Installation de kube-prometheus-stack (release indépendante)
6. Téléchargement des dépendances du chart (loki-stack, velero)
7. Déploiement du chart homepage

> **Idempotent** : si le cluster ou les releases existent déjà, le script effectue un `upgrade`.
> Utilisez `./deploy.sh --reset` pour repartir d'un cluster vierge.

---

## Accès aux services

Les entrées `/etc/hosts` sont ajoutées automatiquement par `deploy.sh`.

| Service | URL | Credentials |
|---------|-----|-------------|
| Homepage | http://homepage.localhost | — |
| Grafana | http://grafana.localhost | admin / adminchangeme |
| Prometheus | http://prometheus.localhost | — |
| AlertManager | http://alertmanager.localhost | — |
| Garage S3 | http://garage.localhost | voir `values.yaml` |

---

## Désinstallation

```bash
helm uninstall homepage --namespace homepage
helm uninstall kube-prometheus-stack --namespace homepage
kubectl delete namespace homepage
kind delete cluster
```

---

## Tests

### Self-healing

```bash
# Supprimer 2 pods simultanément et observer la récupération (~65 secondes)
kubectl delete pods -n homepage -l app.kubernetes.io/name=homepage --grace-period=0
watch kubectl get pods -n homepage
```

### Scaling HPA

```bash
# Lancer une charge HTTP intensive depuis l'intérieur du cluster
kubectl run load-test --image=busybox --restart=Never -n homepage -- \
  sh -c "while true; do wget -q -O- http://homepage.homepage.svc.cluster.local:3000 > /dev/null; done"

# Observer le scale-up (2 → 6 réplicas en ~2 minutes)
watch kubectl get hpa -n homepage

# Supprimer la charge pour observer le scale-down (~5 minutes)
kubectl delete pod load-test -n homepage
```

### Dashboards Grafana

| Dashboard | URL |
|-----------|-----|
| HPA Homepage | http://grafana.localhost/d/homepage-hpa/hpa-scaling-homepage |
| Self-Healing Homepage | http://grafana.localhost/d/homepage-self-healing/self-healing-homepage |

---

## Architecture Helm

```
homepage/
├── Chart.yaml                         # Métadonnées + dépendances (loki-stack, velero)
├── values.yaml                        # Configuration principale
├── values-kube-prometheus-stack.yaml  # Config kube-prometheus-stack (release séparée)
├── deploy.sh                          # Script de déploiement one-command
└── templates/
    ├── configmap.yaml                 # Config Homepage (settings/services/widgets/bookmarks)
    ├── deployment.yaml                # Deployment avec rolling update + probes
    ├── service-ingress.yaml           # Service ClusterIP + Ingress nginx (sticky sessions)
    ├── serviceaccount.yaml            # ServiceAccount + ClusterRole + ClusterRoleBinding
    ├── hpa.yaml                       # HorizontalPodAutoscaler (CPU + mémoire)
    ├── pdb.yaml                       # PodDisruptionBudget
    ├── servicemonitor.yaml            # ServiceMonitor Prometheus
    ├── garage-configmap.yaml          # Config Garage + Secret Velero S3
    ├── garage-statefulset.yaml        # StatefulSet Garage (1 réplica)
    ├── garage-service.yaml            # Services Garage (headless + ClusterIP)
    ├── garage-ingress.yaml            # Ingress Garage S3
    ├── garage-init-job.yaml           # Job init Garage (layout + bucket + key)
    ├── grafana-hpa-homepage-dashboard.yaml
    └── grafana-selfhealing-homepage-dashboard.yaml
```

> **Pourquoi kube-prometheus-stack est installé séparément ?**
> Sa taille dépasse la limite de 1 Mo des Secrets Helm lorsqu'il est inclus comme sub-chart.
> Il est donc géré comme une release Helm indépendante par `deploy.sh`.

---

## Sauvegarde Velero

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
| `podAntiAffinity.mode` | `preferred` | `preferred` (dev/kind) ou `required` (prod) |
| `garage.enabled` | `true` | Active Garage S3 |
| `velero.enabled` | `true` | Active Velero (backup) |
| `loki-stack.enabled` | `true` | Active Loki + Promtail |
