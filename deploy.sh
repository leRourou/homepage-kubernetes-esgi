#!/usr/bin/env bash
# deploy.sh — déploiement complet du projet homepage-kubernetes
# Usage: ./deploy.sh [--reset]
#   --reset : supprime le cluster kind existant avant de recréer

set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="homepage"
RELEASE="homepage"
KPS_RELEASE="kube-prometheus-stack"

# ── Couleurs ──────────────────────────────────────────────────────────────────
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo -e "\n${BLUE}[$(date '+%H:%M:%S')] ── $*${NC}"; }
ok()    { echo -e "${GREEN}  ✓ $*${NC}"; }
warn()  { echo -e "${YELLOW}  ⚠ $*${NC}"; }
die()   { echo -e "${RED}  ✗ $*${NC}" >&2; exit 1; }

# ── Vérification des prérequis ────────────────────────────────────────────────
step "Vérification des prérequis"
for tool in docker kind kubectl helm; do
  command -v "${tool}" &>/dev/null || die "${tool} est requis mais introuvable (brew install ${tool})"
done
ok "docker, kind, kubectl, helm disponibles"

# ── Reset optionnel ───────────────────────────────────────────────────────────
if [[ "${1:-}" == "--reset" ]]; then
  step "Reset : suppression du cluster kind existant"
  kind delete cluster --name kind 2>/dev/null && ok "Cluster supprimé" || warn "Pas de cluster à supprimer"
fi

# ── 1. Cluster kind ───────────────────────────────────────────────────────────
step "1/8 — Cluster kind (1 control-plane + 3 workers)"
if kind get clusters 2>/dev/null | grep -q "^kind$"; then
  warn "Le cluster 'kind' existe déjà — on le réutilise (passez --reset pour repartir de zéro)"
else
  cat <<'EOF' | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  - role: worker
EOF
  ok "Cluster créé"
fi

# ── 2. ingress-nginx ──────────────────────────────────────────────────────────
step "2/8 — ingress-nginx"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
ok "ingress-nginx prêt"

# ── 3. metrics-server (requis pour HPA CPU/RAM) ───────────────────────────────
step "3/8 — metrics-server (pour HPA)"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# kind ne dispose pas de TLS Kubelet valide → on active --kubelet-insecure-tls
kubectl patch deployment metrics-server -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' \
  2>/dev/null || true
kubectl rollout status -n kube-system deployment/metrics-server --timeout=90s
ok "metrics-server prêt"

# ── 4. Dépôts Helm ────────────────────────────────────────────────────────────
step "4/8 — Dépôts Helm"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana             https://grafana.github.io/helm-charts             2>/dev/null || true
helm repo add vmware-tanzu        https://vmware-tanzu.github.io/helm-charts        2>/dev/null || true
helm repo update
ok "Dépôts mis à jour"

# ── 5. Namespace ──────────────────────────────────────────────────────────────
step "5/8 — Namespace ${NAMESPACE}"
kubectl create namespace "${NAMESPACE}" 2>/dev/null || true
ok "Namespace prêt"

# ── 6. kube-prometheus-stack (release indépendante — trop gros comme sub-chart) ─
step "6/8 — kube-prometheus-stack (Prometheus + Grafana + AlertManager)"
echo "  → Cela peut prendre 3–5 minutes sur la première installation..."
helm upgrade --install "${KPS_RELEASE}" prometheus-community/kube-prometheus-stack \
  --namespace "${NAMESPACE}" \
  --version 84.1.0 \
  -f "${CHART_DIR}/values-kube-prometheus-stack.yaml" \
  --wait \
  --timeout 8m
ok "kube-prometheus-stack déployé"

# ── 7. Dépendances du chart (loki-stack + velero) ────────────────────────────
step "7/8 — Dépendances du chart (loki-stack + velero)"
helm dependency update "${CHART_DIR}"
ok "Dépendances prêtes (charts/)"

# ── 8. Chart homepage ─────────────────────────────────────────────────────────
step "8/8 — Chart homepage (Garage + Loki + Velero + Homepage dashboard)"
echo "  → Cela peut prendre 5–10 minutes sur la première installation..."
helm upgrade --install "${RELEASE}" "${CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --wait \
  --timeout 15m
ok "Chart homepage déployé"

# ── /etc/hosts ────────────────────────────────────────────────────────────────
step "Vérification /etc/hosts"
HOSTS_LINE="127.0.0.1  homepage.localhost grafana.localhost prometheus.localhost alertmanager.localhost garage.localhost"
MISSING=false
for domain in homepage.localhost grafana.localhost prometheus.localhost alertmanager.localhost garage.localhost; do
  grep -q "${domain}" /etc/hosts 2>/dev/null || MISSING=true
done

if [ "${MISSING}" = "true" ]; then
  warn "Entrées manquantes dans /etc/hosts — ajout automatique (sudo requis) :"
  echo "    ${HOSTS_LINE}"
  echo "${HOSTS_LINE}" | sudo tee -a /etc/hosts >/dev/null && ok "/etc/hosts mis à jour" || \
    warn "Impossible de modifier /etc/hosts — ajoutez manuellement : ${HOSTS_LINE}"
else
  ok "/etc/hosts déjà configuré"
fi

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Stack déployée avec succès !                        ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Homepage     →  http://homepage.localhost                   ║${NC}"
echo -e "${GREEN}║  Grafana      →  http://grafana.localhost  (admin/adminchangeme) ║${NC}"
echo -e "${GREEN}║  Prometheus   →  http://prometheus.localhost                 ║${NC}"
echo -e "${GREEN}║  AlertManager →  http://alertmanager.localhost               ║${NC}"
echo -e "${GREEN}║  Garage S3    →  http://garage.localhost                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Pods actifs :"
kubectl get pods -n "${NAMESPACE}" --no-headers | sort
