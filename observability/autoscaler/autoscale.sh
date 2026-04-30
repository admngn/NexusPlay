#!/bin/bash
# Autoscaler maison : ajuste le nombre de conteneurs backend en fonction du CPU
# Tourne toutes les 30s via cron sur l'EC2 backend.
# Source de métriques : Prometheus sur l'EC2 nginx.

set -uo pipefail

PROM_URL="${PROM_URL:-http://172.31.83.161:9090}"
TARGET_INSTANCE="172.31.85.135:9100"
MIN_REPLICAS=2
MAX_REPLICAS=5
SCALE_UP_THRESHOLD=70
SCALE_DOWN_THRESHOLD=30
IMAGE="backend"
PORT_BASE=8080

LOG_TAG="[autoscale]"
log() { echo "$(date -u +%FT%TZ) $LOG_TAG $*"; }

# CPU usage en % (1 - idle ratio sur la dernière minute)
QUERY="100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\",instance=\"${TARGET_INSTANCE}\"}[1m])) * 100)"
RAW=$(curl -sG --max-time 5 --data-urlencode "query=${QUERY}" "${PROM_URL}/api/v1/query" 2>/dev/null || true)
if [ -z "$RAW" ]; then
  log "Prometheus indisponible — no-op"
  exit 0
fi

CPU=$(echo "$RAW" | python3 -c "import sys,json
try:
    r = json.load(sys.stdin)['data']['result']
    print(r[0]['value'][1] if r else '')
except Exception:
    print('')" 2>/dev/null)

if [ -z "$CPU" ]; then
  log "Métrique CPU absente — no-op"
  exit 0
fi

CURRENT=$(docker ps --filter "name=^backend-" --format "{{.Names}}" | wc -l | tr -d ' ')
CPU_INT=${CPU%.*}

log "cpu=${CPU}% replicas=${CURRENT} (min=${MIN_REPLICAS}, max=${MAX_REPLICAS})"

if [ "$CPU_INT" -gt "$SCALE_UP_THRESHOLD" ] && [ "$CURRENT" -lt "$MAX_REPLICAS" ]; then
  NEXT=$((CURRENT + 1))
  PORT=$((PORT_BASE + NEXT - 1))
  log "SCALE UP → backend-${NEXT} sur port ${PORT}"
  docker run -d --name "backend-${NEXT}" --restart unless-stopped \
    -p "${PORT}:8080" "${IMAGE}"
elif [ "$CPU_INT" -lt "$SCALE_DOWN_THRESHOLD" ] && [ "$CURRENT" -gt "$MIN_REPLICAS" ]; then
  log "SCALE DOWN → suppression backend-${CURRENT}"
  docker rm -f "backend-${CURRENT}"
else
  log "no-op"
fi
