#!/usr/bin/env bash
# Uso: ./measure.sh <label> <host> <isp> <red:fibra|movil> [muestras=20] [intervalo_s=1]
# Anexa filas a data/raw/curl_<label>.csv
set -euo pipefail
: "${PROBE_TOKEN:?exporta PROBE_TOKEN (terraform output -raw probe_token)}"
label=$1; host=$2; isp=$3; net=$4; n=${5:-20}; gap=${6:-1}
out="$(dirname "$0")/../data/raw/curl_${label}.csv"
[ -f "$out" ] || echo "ts,label,isp,net,path,http_code,connect_s,ttfb_s,total_s" > "$out"
for path in /ping /payload; do
  for ((i=0;i<n;i++)); do
    m=$(curl -s -H "x-probe-token: ${PROBE_TOKEN}" -o /dev/null -w "%{http_code},%{time_connect},%{time_starttransfer},%{time_total}" "http://${host}${path}" || echo "000,,,")
    echo "$(date -u +%FT%TZ),${label},${isp},${net},${path},${m}" >> "$out"
    sleep "$gap"
  done
done
