# wxs-installer

One-command installer for the WXS on-prem stack.

This repo is **intentionally public** so the bootstrap script can be `curl`'d
without authentication. It contains a single file — `install.sh` — which
prompts for a GitHub personal-access token, then uses it to pull the
(private) `wxs-dispatcher` repo and run its interactive installer.

## Customer-facing one-liner

```bash
curl -fsSL https://raw.githubusercontent.com/PendantAutomation/wxs-installer/main/install.sh | sudo bash
```

That's it. The customer is prompted for:

1. Their GitHub PAT (with `repo` + `read:packages` scope).
2. A public hostname (optional — leave blank for HTTP-only).
3. A Cloudflare API token (only if a hostname was set).

Everything else is auto-generated or defaulted.

## What lives where

- `install.sh` (this repo, public) — the bootstrap. Prompts for the PAT,
  downloads `wxs-dispatcher` using it, hands off.
- [`PendantAutomation/wxs-dispatcher`](https://github.com/PendantAutomation/wxs-dispatcher) (private) — the actual dispatcher source. Its `deploy/install.sh` is what runs the rest of the install (Docker, user setup, env file, systemd, Caddy).
- [`PendantAutomation/wxs-3.0`](https://github.com/PendantAutomation/wxs-3.0) (private) — the app itself. The dispatcher pulls its releases at apply time.

## Knobs

`install.sh` honors a couple of env-var overrides for testing:

| Variable | Default | What it does |
|---|---|---|
| `WXS_DISPATCHER_REPO` | `PendantAutomation/wxs-dispatcher` | Override the source repo (handy for forks). |
| `WXS_DISPATCHER_REF` | `master` | Override the branch/tag/commit to install. |

Example: install a feature branch instead of master:

```bash
WXS_DISPATCHER_REF=feature/foo \
  curl -fsSL https://raw.githubusercontent.com/PendantAutomation/wxs-installer/main/install.sh | sudo -E bash
```

(Note the `sudo -E` to preserve the env var.)

## Re-running

Safe to re-run — the bootstrap detects an existing `/opt/wxs/shared/.env`
and reuses its `GITHUB_TOKEN`, and the dispatcher's `deploy/install.sh`
preserves all other secrets too. Re-running effectively upgrades the
dispatcher source itself to the latest `master`.
