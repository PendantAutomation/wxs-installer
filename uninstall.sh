#!/usr/bin/env bash
# WXS one-command uninstaller.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/PendantAutomation/wxs-installer/master/uninstall.sh | sudo bash
#
# Removes:
#   - all WXS docker containers, volumes, and the wxs_net network
#   - the wxs-dispatcher systemd unit
#   - /opt/wxs/ (releases, state, shared, dispatcher, backups, bin)
#   - the wxs system user
#   - Caddy drop-in + /etc/caddy/Caddyfile (restored from .bak.wxs if present)
#   - polkit rule
#   - Cloudflare A record for WXS_HOSTNAME (best-effort)
#
# Leaves alone:
#   - Docker itself
#   - /usr/local/bin/bun
#
# If /opt/wxs/dispatcher/deploy/uninstall.sh exists, this script delegates to
# it (the per-install copy knows the most recent layout). Otherwise we do a
# minimal cleanup inline as a fallback.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  cat >&2 <<EOF
This uninstaller needs to run as root.

Re-run with:
  curl -fsSL https://raw.githubusercontent.com/PendantAutomation/wxs-installer/master/uninstall.sh | sudo bash
EOF
  exit 1
fi

DISPATCHER_UNINSTALL="/opt/wxs/dispatcher/deploy/uninstall.sh"

if [[ -x "$DISPATCHER_UNINSTALL" ]] || [[ -f "$DISPATCHER_UNINSTALL" ]]; then
  echo "Running installed uninstaller at $DISPATCHER_UNINSTALL..."
  exec bash "$DISPATCHER_UNINSTALL" --yes "$@"
fi

# ── Inline fallback ────────────────────────────────────────────────────────
# This path runs when the dispatcher's own uninstall.sh isn't on disk (e.g.
# a partial install). Minimal cleanup: enough to make a fresh install work.

echo "No /opt/wxs/dispatcher present — running inline fallback cleanup."

# Stop + remove WXS containers
if command -v docker >/dev/null 2>&1; then
  managed=$(docker ps -aq --filter "label=wxs.managed-by=wxs-dispatcher" 2>/dev/null || true)
  [[ -n "$managed" ]] && docker rm -f $managed 2>/dev/null || true
  for c in wxs-postgres wxs-electric wxs-neon-proxy wxs-clickhouse wxs-app-blue wxs-app-green; do
    docker rm -f "$c" 2>/dev/null || true
  done
  for v in wxs_postgres_data wxs_electric_data wxs_clickhouse_data wxs_clickhouse_logs; do
    docker volume rm "$v" 2>/dev/null || true
  done
  docker network rm wxs_net 2>/dev/null || true
fi

# Stop dispatcher + remove unit
systemctl stop wxs-dispatcher.service 2>/dev/null || true
systemctl disable wxs-dispatcher.service 2>/dev/null || true
rm -f /etc/systemd/system/wxs-dispatcher.service
systemctl daemon-reload || true

# Caddy bits
systemctl stop caddy.service 2>/dev/null || true
systemctl disable caddy.service 2>/dev/null || true
rm -f /etc/systemd/system/caddy.service.d/wxs.conf
rmdir /etc/systemd/system/caddy.service.d 2>/dev/null || true
if [[ -f /etc/systemd/system/caddy.service ]] && \
   head -1 /etc/systemd/system/caddy.service | grep -q 'Managed by wxs-dispatcher'; then
  rm -f /etc/systemd/system/caddy.service
fi
rm -f /etc/caddy/caddy.env
rm -f /etc/caddy/conf.d/wxs.conf
if [[ -f /etc/caddy/Caddyfile.bak.wxs ]]; then
  mv /etc/caddy/Caddyfile.bak.wxs /etc/caddy/Caddyfile
elif [[ -f /etc/caddy/Caddyfile ]] && head -1 /etc/caddy/Caddyfile | grep -qE 'Managed by wxs-(dispatcher|updater)'; then
  rm /etc/caddy/Caddyfile
fi
userdel caddy 2>/dev/null || true
groupdel caddy 2>/dev/null || true
rm -rf /var/lib/caddy /var/log/caddy
systemctl daemon-reload

# Polkit
rm -f /etc/polkit-1/rules.d/50-wxs.rules
systemctl reload polkit 2>/dev/null || true

# Data root
rm -rf /opt/wxs

# User
id -u wxs >/dev/null 2>&1 && userdel wxs 2>/dev/null || true

echo
echo "✓ Uninstall complete."
