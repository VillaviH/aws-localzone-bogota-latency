#!/usr/bin/env bash
# Uso: ./measure.sh <label> <host> <isp> <red:fibra|movil> [muestras=20] [intervalo_s=1] [proto=http|https] [rutas="/ping /payload"]
# Ejemplos:
#   ./measure.sh bogota     1.2.3.4            MYISP fibra 100 2
#   ./measure.sh bogota     1.2.3.4            MYISP fibra 100 2 https
#   ./measure.sh cloudfront dxxxx.cloudfront.net MYISP fibra 100 2 https "/cached /cached-payload"
# Anexa filas a data/raw/curl_<label>.csv
set -euo pipefail
: "${PROBE_TOKEN:?exporta PROBE_TOKEN (terraform output -raw probe_token)}"
label=$1; host=$2; isp=$3; net=$4; n=${5:-20}; gap=${6:-1}; proto=${7:-http}; paths=${8:-"/ping /payload"}
out="$(dirname "$0")/../data/raw/curl_${label}.csv"
HEADER="ts,label,isp,net,path,http_code,connect_s,ttfb_s,total_s,proto,appconnect_s,pop,cache"

if [ ! -f "$out" ]; then
  echo "$HEADER" > "$out"
elif [ "$(head -1 "$out")" != "$HEADER" ]; then
  # migra CSV con el formato anterior (9 columnas): agrega proto=http y columnas vacías
  tmp=$(mktemp); awk -v h="$HEADER" 'NR==1{print h; next}{print $0",http,,,"}' "$out" > "$tmp"; mv "$tmp" "$out"
fi

kflag=""; [[ $host =~ ^[0-9.]+$ ]] && kflag="-k"   # certificado autofirmado en las EC2

for path in $paths; do
  url="${proto}://${host}${path}"
  curl -s $kflag -H "x-probe-token: ${PROBE_TOKEN}" -o /dev/null "$url" || true   # calentamiento, no se registra
  for ((i=0;i<n;i++)); do
    hdr=$(mktemp)
    m=$(curl -s $kflag -D "$hdr" -H "x-probe-token: ${PROBE_TOKEN}" -o /dev/null \
        -w "%{http_code},%{time_connect},%{time_starttransfer},%{time_total},%{time_appconnect}" "$url") || true
    [ -n "$m" ] || m="000,,,,"
    m=$(printf '%s' "$m" | head -1)
    IFS=, read -r code conn ttfb tot app <<<"$m"
    [ "$proto" = "https" ] || app=""
    pop=$(grep -i '^x-amz-cf-pop:' "$hdr" | tr -d '\r' | awk '{print $2}' || true)
    cache=$(grep -i '^x-cache:' "$hdr" | tr -d '\r' | awk '{print $2}' || true)
    rm -f "$hdr"
    echo "$(date -u +%FT%TZ),${label},${isp},${net},${path},${code},${conn},${ttfb},${tot},${proto},${app},${pop},${cache}" >> "$out"
    sleep "$gap"
  done
done
