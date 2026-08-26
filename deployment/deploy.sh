#!/bin/bash

# smashboard - Deploy to the Raspberry Pi.
#
# Ships the source, installs gems and precompiles assets on the Pi (native gems
# and the Tailwind binary are architecture-specific, so neither can be built
# here), then migrates and restarts.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
[ -f "$SCRIPT_DIR/.env.deploy" ] && source "$SCRIPT_DIR/.env.deploy"

PI_USER=${PI_USER:-pi}
PI_HOST=${PI_HOST:-raspberrypi.local}
DOMAIN_NAME=${DOMAIN_NAME:-dashboard.example.com}
APP_PORT=${APP_PORT:-3012}
RUBY_VERSION=3.4.7

RUN_MIGRATIONS=false
RESTART=true
SKIP_TESTS=false

show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "  --migrate      Back up the database, then run migrations"
    echo "  --no-restart   Deploy without restarting the services"
    echo "  --skip-tests   Don't run the test suite before deploying"
    echo "  --help         Show this message"
    echo ""
    echo "Environment (or .env.deploy): PI_USER, PI_HOST, DOMAIN_NAME, APP_PORT"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --migrate)    RUN_MIGRATIONS=true; shift ;;
        --no-restart) RESTART=false; shift ;;
        --skip-tests) SKIP_TESTS=true; shift ;;
        --help)       show_usage; exit 0 ;;
        *)            print_error "Unknown option: $1"; show_usage; exit 1 ;;
    esac
done

print_status "═══════════════════════════════════════════════"
print_status "  smashboard - Deploy to Raspberry Pi"
print_status "═══════════════════════════════════════════════"
print_status "Target:     $PI_USER@$PI_HOST"
print_status "Domain:     $DOMAIN_NAME"
print_status "Migrations: $RUN_MIGRATIONS"
print_status "═══════════════════════════════════════════════"
echo ""

if ! ssh -o ConnectTimeout=8 -o BatchMode=yes "$PI_USER@$PI_HOST" exit 2>/dev/null; then
    print_error "Cannot reach $PI_USER@$PI_HOST over SSH"
    exit 1
fi

# The install step sources this; without it the failure is a confusing `source`
# error halfway through rather than "you haven't run setup yet".
if ! ssh "$PI_USER@$PI_HOST" "test -f ~/smashboard/.env" 2>/dev/null; then
    print_error "~/smashboard/.env is missing on the Pi — run ./deployment/setup-pi.sh first"
    exit 1
fi

# ─── Test ────────────────────────────────────────────────────────────────

if [ "$SKIP_TESTS" = false ]; then
    print_status "━━━ Running the test suite ━━━"
    cd "$PROJECT_ROOT"
    if ! mise exec ruby@$RUBY_VERSION -- bundle exec rspec --format progress; then
        print_error "Tests failed. Deploy aborted (--skip-tests to override)."
        exit 1
    fi
    print_success "Tests pass"
fi

# ─── Package ─────────────────────────────────────────────────────────────

print_status "━━━ Packaging ━━━"
cd "$PROJECT_ROOT"

ARCHIVE=$(mktemp -d)/smashboard-deploy.tar.gz

# Assets are built on the Pi, so app/assets/builds is deliberately not shipped.
# Nothing secret goes in: the Pi keeps its own ~/smashboard/.env, and shipping a
# local one would both duplicate secrets onto the device and silently override
# whatever the Pi is configured with.
COPYFILE_DISABLE=1 tar -czf "$ARCHIVE" \
    --exclude='.git' \
    --exclude='.github' \
    --exclude='tmp' \
    --exclude='log' \
    --exclude='node_modules' \
    --exclude='vendor/bundle' \
    --exclude='.bundle' \
    --exclude='storage' \
    --exclude='public/assets' \
    --exclude='app/assets/builds/*' \
    --exclude='.env' \
    --exclude='.env.*' \
    --exclude='deployment/.env.deploy' \
    --exclude='config/master.key' \
    --exclude='coverage' \
    --exclude='*.sqlite3*' \
    .

# Belt and braces: never ship a secret, whatever the exclude list did.
if tar -tzf "$ARCHIVE" | grep -qE '(^|/)(\.env(\..*)?|master\.key)$'; then
    print_error "Refusing to deploy: a secret file is in the archive"
    tar -tzf "$ARCHIVE" | grep -E '(^|/)(\.env(\..*)?|master\.key)$'
    exit 1
fi

print_success "Package built ($(du -h "$ARCHIVE" | cut -f1)), no secrets included"

# ─── Upload ──────────────────────────────────────────────────────────────

print_status "━━━ Uploading ━━━"
scp -q "$ARCHIVE" "$PI_USER@$PI_HOST":~/smashboard-deploy.tar.gz
rm -rf "$(dirname "$ARCHIVE")"

# ─── Install ─────────────────────────────────────────────────────────────

print_status "━━━ Installing on the Pi ━━━"
ssh "$PI_USER@$PI_HOST" "bash -s" << ENDSSH
set -euo pipefail

RUBY_BIN="\$HOME/.rbenv/versions/$RUBY_VERSION/bin"
export PATH="\$RUBY_BIN:\$PATH"
cd ~/smashboard

# Extract into a clean directory and swap, rather than untarring over the live
# app. Merging leaves files deleted from the repo alive forever on the device.
rm -rf app.new app.old
mkdir app.new
tar -xzf ~/smashboard-deploy.tar.gz -C app.new
rm ~/smashboard-deploy.tar.gz

if [ -d app ]; then mv app app.old; fi
mv app.new app

# Uploaded files and logs live outside the release so a deploy can't take them
# with it.
mkdir -p ~/smashboard/shared/storage
ln -sfn ~/smashboard/shared/storage ~/smashboard/app/storage
mkdir -p ~/smashboard/app/log ~/smashboard/app/tmp/pids ~/smashboard/app/tmp/cache

set -a; source ~/smashboard/.env; set +a

echo "── Gems ─────────────────────────────────────────────"
cd ~/smashboard/app
bundle config set --local path "\$HOME/smashboard/shared/bundle"
bundle config set --local without 'development test'
bundle config set --local deployment true
bundle install --jobs=4 --retry=3

echo "── Web push keys ────────────────────────────────────"
# Generated on first deploy, once the web-push gem is available. Never
# regenerated: new keys silently invalidate every existing subscription, so
# every device would go quiet until it re-enabled notifications by hand.
if ! grep -qE '^VAPID_PUBLIC_KEY=.+' ~/smashboard/.env; then
    KEYS=\$(bundle exec ruby -e 'require "web-push"; k = WebPush.generate_key; puts k.public_key; puts k.private_key')
    PUB=\$(echo "\$KEYS" | sed -n 1p)
    PRIV=\$(echo "\$KEYS" | sed -n 2p)
    sed -i "s|^VAPID_PUBLIC_KEY=.*|VAPID_PUBLIC_KEY=\$PUB|" ~/smashboard/.env
    sed -i "s|^VAPID_PRIVATE_KEY=.*|VAPID_PRIVATE_KEY=\$PRIV|" ~/smashboard/.env
    echo "  generated a VAPID keypair"
    set -a; source ~/smashboard/.env; set +a
else
    echo "  already configured"
fi

echo "── Assets ───────────────────────────────────────────"
# Tailwind ships a platform-specific binary, so this has to happen here.
bundle exec rails assets:precompile

echo "Install done."
ENDSSH

print_success "Installed"

# ─── Migrate ─────────────────────────────────────────────────────────────

if [ "$RUN_MIGRATIONS" = true ]; then
    print_status "━━━ Backing up the database ━━━"
    ssh "$PI_USER@$PI_HOST" "bash -s" << 'ENDSSH'
set -euo pipefail
BACKUP_DIR=~/smashboard/backups
mkdir -p "$BACKUP_DIR"
STAMP=$(date +%Y%m%d_%H%M%S)

# Only the primary database is dumped. cache, queue and cable are all
# reconstructible: losing them costs a cold cache and any queued job, not data.
if psql -lqtA -F: 2>/dev/null | cut -d: -f1 | grep -qx smashboard_production; then
    FILE="$BACKUP_DIR/smashboard_production_$STAMP.sql.gz"
    pg_dump smashboard_production | gzip > "$FILE"
    echo "  $FILE ($(du -h "$FILE" | cut -f1))"

    cd "$BACKUP_DIR"
    ls -t smashboard_production_*.sql.gz 2>/dev/null | tail -n +11 | xargs -r rm -f
else
    echo "  no database yet — nothing to back up"
fi
ENDSSH
    print_success "Backup complete"

    print_status "━━━ Migrating ━━━"
    ssh "$PI_USER@$PI_HOST" "bash -s" << ENDSSH
set -euo pipefail
export PATH="\$HOME/.rbenv/versions/$RUBY_VERSION/bin:\$PATH"
set -a; source ~/smashboard/.env; set +a
cd ~/smashboard/app
# prepare rather than migrate: it creates and loads the schema on a database
# that doesn't have one yet, and is a plain migrate after that.
bundle exec rails db:prepare
ENDSSH
    print_success "Migrations complete"
fi

# ─── Restart ─────────────────────────────────────────────────────────────

if [ "$RESTART" = true ]; then
    print_status "━━━ Restarting ━━━"
    ssh "$PI_USER@$PI_HOST" "bash -s" << 'ENDSSH'
set -uo pipefail
sudo systemctl restart smashboard-web smashboard-jobs
sleep 2
for unit in smashboard-web smashboard-jobs; do
    printf '  %-18s %s\n' "$unit" "$(systemctl is-active $unit 2>/dev/null)"
done
ENDSSH

    # Polled rather than checked once after a fixed sleep: eager loading on the
    # Pi takes longer than any sleep worth hardcoding, and until Puma binds the
    # port curl fails instantly with a connection refused rather than waiting.
    print_status "Waiting for the app to answer..."
    HTTP=000
    for _ in $(seq 1 30); do
        HTTP=$(ssh "$PI_USER@$PI_HOST" "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:$APP_PORT/up" 2>/dev/null) || HTTP=000
        [ "$HTTP" = "200" ] && break
        sleep 2
    done

    if [ "$HTTP" = "200" ]; then
        print_success "Health check OK (200)"
    else
        print_error "Health check returned $HTTP after 60s"
        print_warning "Logs: ssh $PI_USER@$PI_HOST 'tail -50 ~/smashboard/app/log/production.log'"
        exit 1
    fi
fi

# Only now is the old release unreachable; keep it until the new one is proven.
ssh "$PI_USER@$PI_HOST" "rm -rf ~/smashboard/app.old" 2>/dev/null || true

echo ""
print_status "═══════════════════════════════════════════════"
print_success "Deployed"
print_status "  https://$DOMAIN_NAME"
print_status "═══════════════════════════════════════════════"
print_warning "Logs: ssh $PI_USER@$PI_HOST 'tail -f ~/smashboard/app/log/production.log'"
