#!/usr/bin/env bash
# Mide cuánto tarda la app en Bogotá en hacer N consultas a Virginia (simula una BD en la región padre).
# Uso: ./measure_upstream.sh <ip_bogota> <isp> <red> [muestras=30] [consultas=10] [intervalo_s=1]
# Anexa filas a data/raw/curl_upstream.csv
set -euo pipefail
: "${PROBE_TOKEN:?exporta PROBE_TOKEN}"
host=$1; isp=$2; net=$3; n=${4:-30}; q=${5:-10}; gap=${6:-1}
out="$(dirname "$0")/../data/raw/curl_upstream.csv"
[ -f "$out" ] || echo "ts,isp,net,queries,client_total_ms,upstream_total_ms,per_query_ms" > "$out"
for ((i=0;i<n;i++)); do
  body=$(mktemp)
  t=$(curl -s -H "x-probe-token: ${PROBE_TOKEN}" -o "$body" -w "%{time_total}" "http://${host}/upstream?n=${q}" || echo "")
  total=$(grep -o '"total_ms":[0-9.]*' "$body" | cut -d: -f2 || true)
  per=$(grep -o '"per_query_ms":[0-9.]*' "$body" | cut -d: -f2 || true)
  rm -f "$body"
  [ -n "$total" ] && echo "$(date -u +%FT%TZ),${isp},${net},${q},$(awk "BEGIN{print $t*1000}"),${total},${per}" >> "$out"
  sleep "$gap"
done
