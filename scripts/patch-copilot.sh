#!/usr/bin/env bash
# patch-copilot.sh — Neuter undici assert() calls in the GitHub Copilot CLI
# bundle that cause AssertionError crashes during long-lived sessions.
#
# ROOT CAUSE
# ----------
# The bundled undici HTTP client has race conditions in its HTTP/2 connection
# pool and dispatch loop that cause state invariant violations:
#
#   - client.js _resume():  assert(client[kPending] === 0)  fires when a
#     client is destroyed while requests are still queued (GOAWAY / timeout).
#   - client-h1.js onHttpSocketClose():  assert(client[kRunning] === 0)
#     fires when socket closes before running requests are drained.
#   - client-h2.js:  assert(!this.completed)  fires when late DATA frames
#     arrive after request completion (nodejs/undici#4843).
#   - Pool/Agent dispatchers:  assert(this.callback)  fires when error-rate
#     spikes cause connection churn (nodejs/undici#4059).
#
# These are known upstream bugs (nodejs/undici#4059, #4843, #4846, #3011).
# Active fix PRs exist (e.g. nodejs/undici#4845) but the Copilot CLI bundles
# an older undici snapshot that predates them.
#
# The assertions are debug invariants, NOT control flow — undici's own
# production builds strip them.  When they fire, the process crashes instead
# of allowing the existing error-recovery paths (retry, reconnect) to run.
#
# STRATEGY
# --------
# Find every  require("assert") / require("node:assert")  import that lives
# inside an undici module (identified by proximity to undici-specific symbols)
# and replace it with a self-referencing Proxy no-op:
#
#   (()=>{let a=new Proxy(()=>{},{get:()=>a});return a})()
#
# This is callable (assert(expr) → no-op), supports property access
# (assert.strictEqual(a,b) → no-op), and is infinitely chainable
# (assert.strict.ok(expr) → no-op).  Non-undici assert imports (fetch-spec,
# crypto, cache API, tree-sitter, etc.) are left intact.
#
# SCOPE
# -----
# Patches ~25 undici assert imports per bundle (index.js, sdk/index.js).
# Remaining ~32 non-undici imports per bundle are untouched.
# Includes backup, idempotency check, and node --check syntax validation.
#
# REMOVAL
# -------
# Remove this patch when the Copilot CLI ships an undici version containing
# the fixes from nodejs/undici#4845 and related PRs, or when the bundled
# undici drops assert() calls in its production build.
#
# Usage:
#   ./scripts/patch-copilot.sh            # auto-detect install path
#   ./scripts/patch-copilot.sh /path/to/@github/copilot

set -euo pipefail

# ── Locate the copilot package ────────────────────────────────────────────────
find_package_dir() {
  local npm_root
  npm_root="$(npm root -g 2>/dev/null || true)"
  if [[ -f "$npm_root/@github/copilot/index.js" ]]; then
    echo "$npm_root/@github/copilot"
    return
  fi

  while IFS= read -r bin; do
    local resolved dir
    resolved="$(readlink -f "$bin" 2>/dev/null || true)"
    dir="$(dirname "$resolved")"
    if [[ -f "$dir/index.js" ]]; then
      echo "$dir"
      return
    fi
  done < <(command -v -a copilot 2>/dev/null || true)
}

if [[ $# -ge 1 ]]; then
  COPILOT_DIR="$1"
else
  COPILOT_DIR="$(find_package_dir)"
  if [[ -z "$COPILOT_DIR" ]]; then
    echo "❌  Could not locate the @github/copilot npm package." >&2
    echo "    Pass the package directory explicitly: $0 /path/to/@github/copilot" >&2
    exit 1
  fi
fi

if [[ ! -d "$COPILOT_DIR" ]]; then
  echo "❌  Directory not found: $COPILOT_DIR" >&2
  exit 1
fi

echo "📦  Copilot package: $COPILOT_DIR"

# ── Patch a single JS bundle file ────────────────────────────────────────────
patch_bundle() {
  local file="$1"
  local label
  label="$(basename "$(dirname "$file")")/$(basename "$file")"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  if grep -q '__UNDICI_ASSERT_PATCH__' "$file" 2>/dev/null; then
    echo "  ✅  $label — already patched"
    return 0
  fi

  # Backup
  local backup="${file}.bak"
  if [[ ! -f "$backup" ]]; then
    cp "$file" "$backup"
    echo "  💾  Backup: $backup"
  fi

  local tmp
  tmp="$(mktemp --suffix=.js)"
  cp "$file" "$tmp"

  # Apply patch: replace undici assert imports with no-ops
  local patched
  patched=$(python3 - "$tmp" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Detect which require alias this bundle uses (ve or z)
# by checking which one appears with "node:assert"
req_fn = None
for candidate in ['ve', 'z']:
    if f'{candidate}("node:assert")' in content or f'{candidate}("assert")' in content:
        req_fn = candidate
        break
if req_fn is None:
    print(0)
    sys.exit(0)

# Undici keyword fingerprints — if any appear within 2000 chars of the
# assert import, we know it belongs to undici (not some other module).
UNDICI_KEYWORDS = [
    'kRunning', 'kPending', 'kSize', 'kBusy', 'kConnected', 'kFree',
    'kUrl', 'kClose', 'kDestroy', 'kDispatch', 'kNeedDrain',
    'kKeepAliveTimeout', 'kSocket', 'kClient', 'kHeadersList',
    'kDestroyed', 'kBodyUsed',
    'RequestAbortedError', 'NotSupportedError', 'InvalidArgumentError',
    'SocketError', 'kRetryHandlerDefaultRetry',
    'addSignal', 'removeSignal',
]

# Match every  REQFN("assert")  /  REQFN("node:assert")  occurrence.
# These appear as  var NAME=REQFN(...)  or  ,NAME=REQFN(...)  in var chains.
pattern = re.compile(
    re.escape(req_fn) + r'\("(?:node:)?assert"\)'
)

# No-op replacement: a callable Proxy whose property access returns itself,
# so both  assert(expr)  and  assert.strictEqual(a,b)  become no-ops.
NOOP = '(()=>{let a=new Proxy(()=>{},{get:()=>a});return a})()'

total = 0
for m in reversed(list(pattern.finditer(content))):
    pos = m.start()
    ctx = content[pos:pos+2000]
    if any(kw in ctx for kw in UNDICI_KEYWORDS):
        content = content[:m.start()] + NOOP + content[m.end():]
        total += 1

with open(path, 'w') as f:
    f.write(content)
print(total)
PYEOF
)

  if [[ "$patched" -eq 0 ]]; then
    echo "  ⚠️   $label — no undici assert imports found (already clean or different build)"
    rm -f "$tmp"
    return 0
  fi

  echo "  🔍  $label — neutered $patched undici assert import(s)"

  echo "" >> "$tmp"
  echo "// __UNDICI_ASSERT_PATCH__" >> "$tmp"

  # Syntax check
  if ! node --check "$tmp" 2>/dev/null; then
    echo "  ❌  $label — syntax check failed, restoring backup" >&2
    cp "$backup" "$file"
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$file"
  echo "  ✅  $label — patched successfully"
}

# ── Patch all known bundle files ─────────────────────────────────────────────
ERRORS=0
patch_bundle "$COPILOT_DIR/index.js"     || ERRORS=$((ERRORS + 1))
patch_bundle "$COPILOT_DIR/sdk/index.js" || ERRORS=$((ERRORS + 1))

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "❌  $ERRORS bundle(s) failed to patch." >&2
  exit 1
fi

echo ""
echo "✅  All bundles patched successfully."
