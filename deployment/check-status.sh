#!/bin/bash

# smashboard - What's the deployment doing right now?

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/.env.deploy" ] && source "$SCRIPT_DIR/.env.deploy"

PI_USER=${PI_USER:-pi}
PI_HOST=${PI_HOST:-raspberrypi.local}
DOMAIN_NAME=${DOMAIN_NAME:-dashboard.example.com}
APP_PORT=${APP_PORT:-3012}

print_status "smashboard status — $PI_USER@$PI_HOST"
echo ""

ssh "$PI_USER@$PI_HOST" "bash -s" << ENDSSH
APP_PORT=$APP_PORT
DOMAIN_NAME=$DOMAIN_NAME

echo "── Services ─────────────────────────────────────────"
for unit in smashboard-web smashboard-jobs nginx postgresql; do
    printf '  %-18s %s\n' "\$unit" "\$(systemctl is-active \$unit 2>/dev/null)"
done

echo ""
echo "── Local health check ───────────────────────────────"
printf '  127.0.0.1:%s/up  %s\n' "\$APP_PORT" "\$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:\$APP_PORT/up 2>/dev/null || echo unreachable)"

echo ""
echo "── Certificate ──────────────────────────────────────"
if sudo test -f /etc/letsencrypt/live/\$DOMAIN_NAME/fullchain.pem; then
    sudo openssl x509 -in /etc/letsencrypt/live/\$DOMAIN_NAME/fullchain.pem -noout -enddate | sed 's/^/  /'
else
    echo "  none for \$DOMAIN_NAME"
fi

echo ""
echo "── Databases ────────────────────────────────────────"
for db in smashboard_production smashboard_production_cache smashboard_production_queue smashboard_production_cable; do
    SIZE=\$(psql -tAc "select pg_size_pretty(pg_database_size('\$db'))" 2>/dev/null || echo "missing")
    printf '  %-34s %s\n' "\$db" "\$SIZE"
done

echo ""
echo "── Background jobs ──────────────────────────────────"
psql -d smashboard_production_queue -tAc \
  "select 'ready ' || count(*) from solid_queue_ready_executions" 2>/dev/null | sed 's/^/  /' || echo "  (queue not readable)"
psql -d smashboard_production_queue -tAc \
  "select 'failed ' || count(*) from solid_queue_failed_executions" 2>/dev/null | sed 's/^/  /' || true

echo ""
echo "── Recent errors ────────────────────────────────────"
if [ -f ~/smashboard/app/log/production.log ]; then
    grep -iE 'error|fatal|exception' ~/smashboard/app/log/production.log 2>/dev/null | tail -5 | sed 's/^/  /' || echo "  none"
else
    echo "  no log yet"
fi
ENDSSH

echo ""
print_status "── From here ────────────────────────────────────────"
HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$DOMAIN_NAME/up" 2>/dev/null || echo "000")
if [ "$HTTP" = "200" ]; then
    print_success "https://$DOMAIN_NAME/up → 200"
else
    print_error "https://$DOMAIN_NAME/up → $HTTP"
fi
