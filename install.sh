#!/usr/bin/env bash
# WXS one-command bootstrap installer.
#
# Usage (on a fresh customer box):
#
#   curl -fsSL https://raw.githubusercontent.com/PendantAutomation/wxs-installer/main/install.sh | sudo bash
#
# This script:
#   1. Prompts for the GitHub personal-access token (the dispatcher repo is
#      private and we don't bake credentials into anything public).
#   2. Downloads the latest wxs-dispatcher tarball using that token.
#   3. Hands off to the dispatcher's own `deploy/install.sh`, which asks the
#      remaining 2 questions (hostname / Cloudflare) and generates all
#      secrets automatically.
#
# Everything else — Docker install, user creation, env file, systemd units,
# Caddy — happens inside deploy/install.sh. This file's only job is the
# bootstrap auth + tarball fetch.

set -euo pipefail

DISPATCHER_REPO="${WXS_DISPATCHER_REPO:-PendantAutomation/wxs-dispatcher}"
DISPATCHER_REF="${WXS_DISPATCHER_REF:-master}"

# ── Sanity checks ───────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
  cat >&2 <<EOF
This installer needs to run as root.

Re-run with:
  curl -fsSL https://raw.githubusercontent.com/PendantAutomation/wxs-installer/main/install.sh | sudo bash
EOF
  exit 1
fi

# Reading from /dev/tty bypasses stdin (which curl|bash takes over).
if [[ ! -e /dev/tty ]]; then
  echo "no controlling terminal — re-run from an interactive shell" >&2
  exit 1
fi

for tool in curl tar; do
  command -v "$tool" >/dev/null || { echo "missing required tool: $tool" >&2; exit 1; }
done

# ── Prompt for the PAT ──────────────────────────────────────────────────────

cat <<'BANNER'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                          WXS one-command installer
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This will install the WXS dispatcher and bring up the full app stack
(Postgres + ElectricSQL + ClickHouse + app) on this host via Docker.

First we need your GitHub personal-access token. It needs:
  • repo            (to download dispatcher source + check for releases)
  • read:packages   (to pull the app container image from GHCR)

Create one at: https://github.com/settings/tokens/new

BANNER

# Pre-fill with an existing token if /opt/wxs/shared/.env already has one
# (e.g. re-running the installer to upgrade the dispatcher itself).
EXISTING_ENV="/opt/wxs/shared/.env"
EXISTING_TOKEN=""
if [[ -f "$EXISTING_ENV" ]]; then
  EXISTING_TOKEN=$(grep -E '^GITHUB_TOKEN=' "$EXISTING_ENV" | head -1 | cut -d= -f2- || true)
fi

if [[ -n "$EXISTING_TOKEN" ]]; then
  echo "Found existing token in $EXISTING_ENV — reusing it."
  TOKEN="$EXISTING_TOKEN"
else
  read -r -s -p "GitHub PAT (hidden): " TOKEN </dev/tty
  echo
  if [[ -z "$TOKEN" ]]; then
    echo "no token entered — aborting" >&2
    exit 1
  fi
fi
echo

# ── Verify the token can actually reach the dispatcher repo ────────────────
echo "Verifying token..."
http_status=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$DISPATCHER_REPO")

case "$http_status" in
  200) echo "✓ Token works." ;;
  401) echo "✗ Token rejected (401 Unauthorized) — check it has 'repo' scope." >&2; exit 1 ;;
  404) echo "✗ Repo $DISPATCHER_REPO not found, or your token can't see it." >&2; exit 1 ;;
  *)   echo "✗ Unexpected response $http_status from GitHub." >&2; exit 1 ;;
esac

# ── Download + extract dispatcher source ───────────────────────────────────

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "Downloading $DISPATCHER_REPO@$DISPATCHER_REF..."
curl -fsSL \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$DISPATCHER_REPO/tarball/$DISPATCHER_REF" \
  | tar -xz -C "$WORK"

# GitHub tarballs extract into a directory like "<org>-<repo>-<sha>/"
SRC_DIR=$(find "$WORK" -mindepth 1 -maxdepth 1 -type d | head -1)
if [[ -z "$SRC_DIR" || ! -f "$SRC_DIR/deploy/install.sh" ]]; then
  echo "✗ tarball didn't contain deploy/install.sh — repo layout changed?" >&2
  exit 1
fi
echo "✓ Extracted to $SRC_DIR"

# ── Hand off to the dispatcher's interactive installer ─────────────────────

# Pass the token via env so deploy/install.sh skips its own GitHub prompt.
# The script also reads from /dev/tty for the remaining 2 prompts (hostname
# / Cloudflare), so the user only gets asked things curl|bash can't answer.
export GITHUB_TOKEN="$TOKEN"
export WXS_BOOTSTRAP=1   # signal to deploy/install.sh that we're curl|bash

echo
echo "Handing off to the dispatcher's installer..."
echo
cd "$SRC_DIR"
bash deploy/install.sh
