#!/usr/bin/env bash
#
# Installs the usage reporter on the machine you run Claude Code on.
# Run it from a checkout of smashboard, on that machine.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_DIR="$HOME/.config/smashboard"
UNIT_DIR="$HOME/.config/systemd/user"

command -v jq  >/dev/null || { echo "jq is required"; exit 1; }
command -v curl >/dev/null || { echo "curl is required"; exit 1; }

echo "Installing the reporter..."
sudo install -m 0755 "$PROJECT_ROOT/script/smashboard-usage-reporter" /usr/local/bin/smashboard-usage-reporter

mkdir -p "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/reporter.env" ]; then
    # Deliberately no default: this writes a timer that POSTs your usage every ten
    # minutes, so the destination has to be a host you named on purpose. A default
    # here would quietly ship one person's data to whoever's URL shipped with the
    # checkout.
    read -rp "smashboard URL (e.g. https://dashboard.example.com): " url
    [ -n "$url" ] || { echo "A smashboard URL is required."; exit 1; }
    read -rsp "smashboard API token (from /api_tokens): " token; echo
    [ -n "$token" ] || { echo "An API token is required."; exit 1; }
    umask 077
    cat > "$CONFIG_DIR/reporter.env" <<ENVEOF
SMASHBOARD_URL=$url
SMASHBOARD_API_TOKEN=$token
ENVEOF
    chmod 600 "$CONFIG_DIR/reporter.env"
    echo "Wrote $CONFIG_DIR/reporter.env (mode 600)"
else
    echo "$CONFIG_DIR/reporter.env exists — left alone"
fi

mkdir -p "$UNIT_DIR"
install -m 0644 "$SCRIPT_DIR/smashboard-usage-reporter.service" "$UNIT_DIR/"
install -m 0644 "$SCRIPT_DIR/smashboard-usage-reporter.timer" "$UNIT_DIR/"

systemctl --user daemon-reload
systemctl --user enable --now smashboard-usage-reporter.timer

echo "Reporting one now to check it works..."
/usr/local/bin/smashboard-usage-reporter

echo
echo "Done. The timer runs every 10 minutes."
echo "  status: systemctl --user status smashboard-usage-reporter.timer"
echo "  logs:   journalctl --user -u smashboard-usage-reporter -n 20"
