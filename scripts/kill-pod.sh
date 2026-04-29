#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-homepage}"

pods=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=homepage --no-headers | grep Running | awk '{print $1}')
count=$(echo "${pods}" | wc -l)

if [[ -z "${pods}" ]]; then
  echo "Aucun pod Running trouvé."
  exit 1
fi

target=$(echo "${pods}" | head -1)
echo "==> ${count} pod(s) Running. Suppression de : ${target}"

kubectl delete pod "${target}" -n "${NAMESPACE}"
echo "==> Pod supprimé. Surveille le self-healing :"
echo ""

for i in $(seq 1 12); do
  sleep 5
  status=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=homepage --no-headers 2>/dev/null)
  echo "[$(date '+%H:%M:%S')]"
  echo "${status}"
  echo ""
  running=$(echo "${status}" | grep -c "Running" || true)
  if [[ "${running}" -ge "${count}" ]]; then
    echo "==> Self-healing OK — ${running} pod(s) Running."
    exit 0
  fi
done

echo "==> Timeout : vérifie manuellement avec : kubectl get pods -n ${NAMESPACE}"
exit 1
