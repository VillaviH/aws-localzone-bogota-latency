#!/usr/bin/env bash
# Uso: ./measure.sh <label> <host> <isp> <red:fibra|movil> [muestras=20] [intervalo_s=1] [proto=http|https] [rutas="/ping /payload"]
# Ejemplos:
#   ./measure.sh bogota     1.2.3.4            MYISP fibra 100 2
#   ./measure.sh bogota     1.2.3.4            MYISP fibra 100 2 https
#   EXTRA_QUERY=target=parent ./measure.sh bogota-parent-alb <dns-alb-bogota> MYISP fibra 100 2 http "/api/read?obj=large"   # app en Bogotá, bucket regional
#   ./measure.sh bogota-alb <dns-del-alb>      MYISP fibra 100 2 http "/ping /api/read?obj=small /api/read?obj=large /api/write?obj=large"
# Anexa filas a data/raw/curl_<label>.csv
set -euo pipefail
: "${PROBE_TOKEN:?exporta PROBE_TOKEN (terraform output -raw probe_token)}"
label=$1; host=$2; isp=$3; net=$4; n=${5:-20}; gap=${6:-1}; proto=${7:-http}; paths=${8:-"/ping /payload"}
out="$(dirname "$0")/../data/raw/curl_${label}.csv"
HEADER="ts,label,isp,net,path,http_code,connect_s,ttfb_s,total_s,proto,appconnect_s,s3_ms"

if [ ! -f "$out" ]; then
  echo "$HEADER" > "$out"
elif [ "$(head -1 "$out")" != "$HEADER" ]; then
  # migra formatos anteriores: 9, 11 o 13 columnas -> 12 columnas
  tmp=$(mktemp)
  awk -F, -v OFS=, -v h="$HEADER" 'NR==1{print h; next} NF==9{print $0,"http","",""; next} NF==11{print $0,""; next} {print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,""}' "$out" > "$tmp"
  mv "$tmp" "$out"
fi

kflag=""; [[ $host =~ ^[0-9.]+$ ]] && kflag="-k"   # certificado autofirmado en las EC2

for path in $paths; do
  url="${proto}://${host}${path}"
  if [ -n "${EXTRA_QUERY:-}" ]; then case "$path" in *\?*) url="${url}&${EXTRA_QUERY}";; *) url="${url}?${EXTRA_QUERY}";; esac; fi
  curl -s $kflag -H "x-probe-token: ${PROBE_TOKEN}" -o /dev/null "$url" || true   # calentamiento, no se registra
  for ((i=0;i<n;i++)); do
    hdr=$(mktemp)
    m=$(curl -s $kflag -D "$hdr" -H "x-probe-token: ${PROBE_TOKEN}" -o /dev/null \
        -w "%{http_code},%{time_connect},%{time_starttransfer},%{time_total},%{time_appconnect}" "$url") || true
    [ -n "$m" ] || m="000,,,,"
    m=$(printf '%s' "$m" | head -1)
    IFS=, read -r code conn ttfb tot app <<<"$m"
    [ "$proto" = "https" ] || app=""
    s3ms=$(grep -i "^server-timing:" "$hdr" | tr -d '\r' | sed -n 's/.*s3;dur=\([0-9.]*\).*/\1/p' || true)
    rm -f "$hdr"
    echo "$(date -u +%FT%TZ),${label},${isp},${net},${path},${code},${conn},${ttfb},${tot},${proto},${app},${s3ms}" >> "$out"
    sleep "$gap"
  done
done
