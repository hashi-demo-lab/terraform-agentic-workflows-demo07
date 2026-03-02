#!/usr/bin/env bash
# patch-copilot.sh — Remove overly-strict undici dispatch assertions from the
# GitHub Copilot CLI bundle that cause AssertionError on Node.js v25+.
#
# Usage:
#   ./scripts/patch-copilot.sh            # auto-detect install path
#   ./scripts/patch-copilot.sh /path/to/@github/copilot

set -euo pipefail

# ── Locate the copilot package ────────────────────────────────────────────────
find_package_dir() {
  # 1. npm global root (most reliable — avoids picking up VS Code shims)
  local npm_root
  npm_root="$(npm root -g 2>/dev/null || true)"
  if [[ -f "$npm_root/@github/copilot/index.js" ]]; then
    echo "$npm_root/@github/copilot"
    return
  fi

  # 2. Walk every 'copilot' on PATH looking for one whose resolved target
  #    sits next to an index.js (i.e. the npm-loader symlink pattern).
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
# Usage: patch_bundle <path>
# Returns 0 if patched or already clean, 1 on failure.
patch_bundle() {
  local file="$1"
  local label
  label="$(basename "$(dirname "$file")")/$(basename "$file")"

  if [[ ! -f "$file" ]]; then
    return 0   # optional file, skip silently
  fi

  # Idempotency marker
  if grep -q '__PATCH_APPLIED__' "$file" 2>/dev/null; then
    echo "  ✅  $label — already patched"
    return 0
  fi

  # Count matching patterns (all known assertion forms in undici client/pool)
  local count
  count=$(python3 -c "
import re
with open('$file', 'r') as f:
    content = f.read()
patterns = [
    re.compile(r'for\(;;\)\{if\(t\.destroyed\)\{\w+\(t\[\w+\]===0\);return\}'),
    re.compile(r't\.destroyed\)\{\w+\(t\[\w+\]===0\);let '),
    re.compile(r'\}\w+\(t\[\w+\]===0\)\}\}function'),
    re.compile(r'for\(\w+\(t\[\w+\]===0\);'),
    re.compile(r',\w+\(t\[\w+\]===0\),t\.emit\(\"disconnect\"'),
]
print(sum(len(p.findall(content)) for p in patterns))
")

  if [[ "$count" -eq 0 ]]; then
    echo "  ⚠️   $label — no assertion patterns found (already clean or different build)"
    return 0
  fi

  echo "  🔍  $label — found $count assertion(s)"

  # Backup
  local backup="${file}.bak"
  if [[ ! -f "$backup" ]]; then
    cp "$file" "$backup"
    echo "  💾  Backup: $backup"
  fi

  # Apply patch via Python (robust to any minified variable names)
  local tmp patched
  tmp="$(mktemp --suffix=.js)"
  cp "$file" "$tmp"

  patched=$(python3 - "$tmp" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()
patches = [
    # for(;;){if(t.destroyed){FUNC(t[x]===0);return}
    (re.compile(r'(for\(;;\)\{if\(t\.destroyed\)\{)\w+\(t\[\w+\]===0\);(return\})'), r'\1\2'),
    # if(...,t.destroyed){FUNC(t[x]===0);let   — destroy path before splice
    (re.compile(r'(t\.destroyed\)\{)\w+\(t\[\w+\]===0\);(let )'), r'\1\2'),
    # }FUNC(t[x]===0)}}function  — end of error-flush loop
    (re.compile(r'(\})\w+\(t\[\w+\]===0\)(\}\}function)'), r'\1\2'),
    # for(FUNC(t[x]===0);  — TLS cert-altname error loop initialiser
    (re.compile(r'for\(\w+\(t\[\w+\]===0\);'), r'for(;'),
    # ,FUNC(t[x]===0),t.emit("disconnect"  — disconnect handler
    (re.compile(r',\w+\(t\[\w+\]===0\)(,t\.emit\("disconnect")'), r'\1'),
]
total = 0
for pattern, repl in patches:
    content, n = pattern.subn(repl, content)
    total += n
with open(path, 'w') as f:
    f.write(content)
print(total)
PYEOF
)

  echo "" >> "$tmp"
  echo "// __PATCH_APPLIED__" >> "$tmp"

  # Verify
  local remaining
  remaining=$(python3 -c "
import re
with open('$tmp', 'r') as f:
    content = f.read()
patterns = [
    re.compile(r'for\(;;\)\{if\(t\.destroyed\)\{\w+\(t\[\w+\]===0\);return\}'),
    re.compile(r't\.destroyed\)\{\w+\(t\[\w+\]===0\);let '),
    re.compile(r'\}\w+\(t\[\w+\]===0\)\}\}function'),
    re.compile(r'for\(\w+\(t\[\w+\]===0\);'),
    re.compile(r',\w+\(t\[\w+\]===0\),t\.emit\(\"disconnect\"'),
]
print(sum(len(p.findall(content)) for p in patterns))
")

  if [[ "$remaining" -gt 0 ]]; then
    echo "  ❌  $label — $remaining assertion(s) still present after patch!" >&2
    rm -f "$tmp"
    return 1
  fi

  if ! node --check "$tmp" 2>/dev/null; then
    echo "  ❌  $label — syntax check failed, restoring backup" >&2
    cp "$backup" "$file"
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$file"
  echo "  🔧  $label — removed $patched assertion(s) ✅"
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
