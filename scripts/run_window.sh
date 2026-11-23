#!/usr/bin/env bash
# Corre toda la batería de pruebas de una ventana de medición, con una sola orden.
# Uso: ./scripts/run_window.sh <ISP> <fibra|movil> [muestras=100] [intervalo_s=2]
# Lee IPs, DNS de los ALB y token desde `terraform output`. Dura unos 28 min con los valores por defecto.
set -euo pipefail
isp=${1:?uso: run_window.sh <ISP> <fibra|movil> [muestras] [intervalo]}; net=${2:?falta fibra|movil}
n=${3:-100}; gap=${4:-2}
root="$(cd "$(dirname "$0")/.." && pwd)"; tf="terraform -chdir=$root/infra/terraform output -raw"
export PROBE_TOKEN=$($tf probe_token)
B=$($tf bogota_ip); V=$($tf virginia_ip); BA=$($tf bogota_alb); VA=$($tf virginia_alb)
P="/api/read?obj=small /api/read?obj=large /api/write?obj=large"
m="$root/scripts/measure.sh"
say() { echo; echo "[$(date +%H:%M:%S)] $*"; }

say "1/4  Aplicación completa vía ALB (Bogotá, Virginia y Bogotá con bucket regional)"
"$m" bogota-alb   "$BA" "$isp" "$net" "$n" "$gap" http "/ping $P" &
"$m" virginia-alb "$VA" "$isp" "$net" "$n" "$gap" http "/ping $P" &
EXTRA_QUERY=target=parent "$m" bogota-parent-alb "$BA" "$isp" "$net" "$n" "$gap" http "$P" &
wait
say "2/4  Directo a la EC2, HTTP"
"$m" bogota   "$B" "$isp" "$net" "$n" "$gap" http & "$m" virginia "$V" "$isp" "$net" "$n" "$gap" http & wait
say "3/4  Directo a la EC2, HTTPS"
"$m" bogota   "$B" "$isp" "$net" "$n" "$gap" https & "$m" virginia "$V" "$isp" "$net" "$n" "$gap" https & wait
say "4/4  App en Bogotá consultando a Virginia"
"$root/scripts/measure_upstream.sh" "$B" "$isp" "$net" "$(( n < 30 ? n : 30 ))" 10 1
say "Listo. Abre el dashboard: http://localhost:8000/dashboard.html"
