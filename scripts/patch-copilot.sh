#!/usr/bin/env bash
# patch-copilot.sh — Remove overly-strict undici dispatch assertions from the
# GitHub Copilot CLI bundle that cause AssertionError on Node.js v25+.
#
# Usage:
#   ./scripts/patch-copilot.sh            # auto-detect install path
#   ./scripts/patch-copilot.sh /path/to/@github/copilot

set -euo pipefail

# ── Locate the copilot package ────────────────────────────────────────────────
if [[ $# -ge 1 ]]; then
  COPILOT_DIR="$1"
else
  COPILOT_BIN="$(command -v copilot 2>/dev/null || true)"
  if [[ -z "$COPILOT_BIN" ]]; then
    echo "❌  'copilot' not found in PATH. Pass the package directory explicitly." >&2
    exit 1
  fi
  # Resolve symlink: .../bin/copilot -> .../lib/node_modules/@github/copilot/npm-loader.js
  COPILOT_DIR="$(dirname "$(readlink -f "$COPILOT_BIN")")"
fi

INDEX="$COPILOT_DIR/index.js"

if [[ ! -f "$INDEX" ]]; then
  echo "❌  index.js not found at: $INDEX" >&2
  exit 1
fi

echo "📦  Copilot bundle: $INDEX"

# ── Already patched? ─────────────────────────────────────────────────────────
if grep -q '__PATCH_APPLIED__' "$INDEX" 2>/dev/null; then
  echo "✅  Patch already applied — nothing to do."
  exit 0
fi

# ── Check that the known assertion patterns are present ──────────────────────
H1_NEEDLE='function Hdo(t,e){for(;;){if(t.destroyed){OJ(t[HNe]===0);return}'
H2_NEEDLE='function EWo(t,e){for(;;){if(t.destroyed){vs(t[qq]===0);return}'

H1_FOUND=false
H2_FOUND=false
grep -qF "$H1_NEEDLE" "$INDEX" && H1_FOUND=true
grep -qF "$H2_NEEDLE" "$INDEX" && H2_FOUND=true

if ! $H1_FOUND && ! $H2_FOUND; then
  echo "⚠️   Neither assertion pattern found — the bundle may already be fixed or uses different variable names."
  echo "    No changes made."
  exit 0
fi

# ── Backup ────────────────────────────────────────────────────────────────────
BACKUP="${INDEX}.bak"
if [[ ! -f "$BACKUP" ]]; then
  cp "$INDEX" "$BACKUP"
  echo "💾  Backup saved: $BACKUP"
else
  echo "💾  Backup already exists: $BACKUP"
fi

# ── Apply patches ─────────────────────────────────────────────────────────────
TMP="$(mktemp)"
cp "$INDEX" "$TMP"

if $H1_FOUND; then
  sed -i 's|function Hdo(t,e){for(;;){if(t\.destroyed){OJ(t\[HNe\]===0);return}|function Hdo(t,e){for(;;){if(t.destroyed){return}|g' "$TMP"
  echo "🔧  Patched H1 dispatcher (Hdo): removed OJ(t[HNe]===0) assertion"
fi

if $H2_FOUND; then
  sed -i 's|function EWo(t,e){for(;;){if(t\.destroyed){vs(t\[qq\]===0);return}|function EWo(t,e){for(;;){if(t.destroyed){return}|g' "$TMP"
  echo "🔧  Patched H2 dispatcher (EWo): removed vs(t[qq]===0) assertion"
fi

# Stamp so re-runs are idempotent
echo "" >> "$TMP"
echo "// __PATCH_APPLIED__" >> "$TMP"

mv "$TMP" "$INDEX"

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
echo "🔍  Verifying patch..."
ERRORS=0

if $H1_FOUND && grep -qF "$H1_NEEDLE" "$INDEX"; then
  echo "❌  H1 assertion still present!" >&2
  ERRORS=$((ERRORS + 1))
fi
if $H2_FOUND && grep -qF "$H2_NEEDLE" "$INDEX"; then
  echo "❌  H2 assertion still present!" >&2
  ERRORS=$((ERRORS + 1))
fi

if [[ $ERRORS -gt 0 ]]; then
  echo "❌  Patch failed. Restoring backup..." >&2
  cp "$BACKUP" "$INDEX"
  exit 1
fi

# Quick syntax check
if ! node --check "$INDEX" 2>/dev/null; then
  echo "❌  Syntax check failed. Restoring backup..." >&2
  cp "$BACKUP" "$INDEX"
  exit 1
fi

echo "✅  Patch applied and verified successfully."
