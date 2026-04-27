# Plan d'implémentation — Homepage Infrastructure Dashboard

## Objectif
Dashboard Infrastructure Kubernetes : portail central de supervision du cluster avec Prometheus, Grafana et Loki.

---

## Phases

### Phase 1 — Stack monitoring (Helm dependencies) `[x]`
- Ajouté `kube-prometheus-stack` v84.1.0 (prometheus-community) comme dépendance dans `Chart.yaml`
- Ajouté `loki-stack` v2.10.3 (grafana) comme dépendance dans `Chart.yaml`
- Configuré dans `values.yaml` :
  - Prometheus : rétention 15d / 4GB, PVC 5Gi
  - Grafana : password `adminchangeme`, persistence 2Gi, timezone Europe/Paris
  - AlertManager : PVC 1Gi
  - Loki : persistence 5Gi, rétention logs 168h
  - Promtail activé ; composants inutiles sur kind désactivés (kubeControllerManager, kubeScheduler, kubeEtcd, kubeProxy)
- `helm dependency update` exécuté — archives dans `charts/`
- Déployé dans namespace `homepage` (revision 16)
- **Résultat** : AlertManager ✅, Operator ✅, kube-state-metrics ✅, Node Exporter x3 ✅, Loki ✅, Promtail x3 ✅, Grafana ⏳ init, Prometheus ⚠️ ImagePullBackOff réseau (retente auto)

### Phase 2 — Dashboard Homepage `[x]`
- `services.yaml` : section Infrastructure ajoutée — Grafana (widget grafana), Prometheus (widget prometheus), AlertManager (widget alertmanager), Kubernetes
- `widgets.yaml` : widget `kubernetes` ajouté — cluster (CPU/RAM) + nodes (CPU/RAM/label)
- URLs internes cluster.local utilisées (services dans namespace `homepage`)
- Credentials Grafana : admin / adminchangeme
- **Résultat** : ConfigMap `homepage-config` mis à jour (revision 17), pods homepage rechargent la config automatiquement

### Phase 3 — ServiceMonitor `[x]`
- Créé `templates/servicemonitor.yaml` : label `release: homepage` (requis par le selector Prometheus), port `http`, interval 30s
- Ajouté `serviceMonitor.enabled/interval/scrapeTimeout` dans `values.yaml`
- Ajouté `allowedHosts: "*"` pour que les pods soient accessibles depuis les scrapers internes
- **Résultat** : 6 targets homepage visibles dans Prometheus (`/targets`, job=`homepage`). Statut `down` attendu — homepage ne expose pas de métriques Prometheus, mais la découverte via ServiceMonitor fonctionne.

### Phase 4 — Tests self-healing et scaling `[x]`

#### Test 1 — Self-healing
- Supprimé 2 pods simultanément avec `--grace-period=0` (1 par node : `homepage-worker` + `homepage-worker2`)
- ReplicaSet recréé 2 remplaçants immédiatement (scheduling instantané, image déjà en cache kind)
- **Résultat** : recovery complète en **~65 secondes** (pod créé ~0s, readiness probe passée ~65s)
- Distribution inter-nodes maintenue automatiquement

#### Test 2 — Scaling HPA
- Contexte initial : HPA 6/6 bloqué par mémoire (74%/80%) — CPU à 2%
- Patch HPA temporaire : CPU-only (70%), scale-down window 30s
- **Scale-down** : 6 → 2 réplicas en **~16 secondes** (CPU 2% << 70%)
- Charge appliquée : 20 boucles wget parallèles (busybox) → CPU grimpe à **247%/70%**
- **Scale-up** : 2 → 4 → 6 réplicas en **~2 minutes** (stabilisation 30s + 2 pods/30s)
- Charge supprimée → CPU retombe à 3%
- **Scale-down** : 6 → 2 réplicas en **~30 secondes** (fenêtre stabilisation configurée)
- HPA restauré avec métriques CPU+mémoire et comportement d'origine (300s scale-down)

### Phase 5 — Service ntfy `[ ]`
- Ajout de ntfy (serveur de notifications push self-hosted) comme service démonstratif
- Nouveaux templates : `ntfy-deployment.yaml`, `ntfy-service-ingress.yaml`, `ntfy-hpa.yaml`, `ntfy-pdb.yaml`, `ntfy-servicemonitor.yaml`
- HPA CPU-only (70%), min 1 / max 4 réplicas — démo scaling par flood HTTP POST
- Liveness + readiness probes sur `/v1/health` — démo self-healing par suppression pod ou kill process
- Accessible via `http://ntfy.localhost`, affiché dans Homepage (catégorie "Services") avec badge ping
- Commandes démo scaling : `kubectl run ntfy-load` (wget loop interne) + `watch kubectl get hpa`
- Commandes démo self-healing : `kubectl delete pods --grace-period=0` ou `kubectl exec -- kill 1`

### Phase 6 — Documentation `[ ]`
- Architecture Kubernetes avec diagramme
- Guide d'installation complet (prérequis, commandes, vérifications)
- Analyse des tests self-healing et scaling (avant/après, métriques) — inclure ntfy

---

## Etat du chart au démarrage

| Composant | Statut |
|-----------|--------|
| Deployment (rolling update, probes, security context) | ✅ |
| ConfigMap (settings/services/widgets/bookmarks) | ✅ |
| HPA (CPU + Memory, scale 2→6) | ✅ |
| PDB (minAvailable: 1) | ✅ |
| Service + Ingress nginx (sticky sessions, TLS) | ✅ |
| ServiceAccount + ClusterRole/Binding (k8s discovery) | ✅ |
| Stack monitoring (Prometheus/Grafana/Loki) | ✅ |
| Dashboard Infrastructure Homepage | ✅ |
| ServiceMonitor (Prometheus scrape homepage) | ✅ |
| Velero (backup) | ❌ |
