#!/usr/bin/env bash
set -euo pipefail

HOST="${HOST:-homepage.localhost}"
CONCURRENCY="${CONCURRENCY:-50}"
DURATION="${DURATION:-120}"
INTERVAL="${INTERVAL:-5}"

if ! command -v hey &>/dev/null && ! command -v ab &>/dev/null; then
  echo "Installe 'hey' (go install github.com/rakyll/hey@latest) ou 'ab' (apache2-utils)"
  exit 1
fi

echo "==> Stress test sur http://${HOST} — ${CONCURRENCY} workers pendant ${DURATION}s"
echo "==> Surveille : kubectl get hpa homepage -n homepage -w"
echo ""

watch_hpa() {
  while true; do
    replicas=$(kubectl get hpa homepage -n homepage --no-headers 2>/dev/null | awk '{print $6, "->", $7}')
    echo "[$(date '+%H:%M:%S')] replicas: ${replicas}"
    sleep "${INTERVAL}"
  done
}

watch_hpa &
WATCH_PID=$!
trap "kill ${WATCH_PID} 2>/dev/null" EXIT

if command -v hey &>/dev/null; then
  hey -c "${CONCURRENCY}" -z "${DURATION}s" "http://${HOST}"
else
  ab -c "${CONCURRENCY}" -t "${DURATION}" "http://${HOST}/"
fi

echo ""
echo "==> Stress test terminé. L'HPA va scaler down sous ~60s."
