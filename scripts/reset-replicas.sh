#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-homepage}"
REPLICAS="${REPLICAS:-2}"

current=$(kubectl get deployment homepage -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null)
echo "==> Réplicas actuels : ${current} — cible : ${REPLICAS}"

kubectl scale deployment homepage -n "${NAMESPACE}" --replicas="${REPLICAS}"
echo "==> Scale forcé à ${REPLICAS} réplicas."

echo -n "==> Attente que les pods soient prêts"
kubectl rollout status deployment/homepage -n "${NAMESPACE}" --timeout=60s
echo ""
echo "==> OK — $(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=homepage --no-headers | grep Running | wc -l) pod(s) Running."
