#!/usr/bin/env bash
# publish-module-version.sh — Publish a new PMR module version by tagging the source repo
#
# What this does:
#   1. Creates a git tag (vX.Y.Z) on the source module repo via GitHub API
#   2. Waits for TFC to ingest the new version (polls the PMR API)
#   3. Updates MODULE_TARGET_VERSION in demo.env
#
# The PMR module is VCS-connected — TFC automatically publishes new versions
# when semver tags (vX.Y.Z) are pushed to the source repo.
#
# Prerequisites:
#   - gh CLI authenticated (needs push access to the source module repo)
#   - TFE_TOKEN environment variable set
#   - demo.env configured with MODULE_SOURCE
#
# Usage:
#   bash specs/feat-consumer-uplift/demo/publish-module-version.sh [--version 5.8.3]
#
# If --version is omitted, auto-increments the patch version from MODULE_CURRENT_VERSION.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Color helpers ───────────────────────────────────────────────────────────
C_CYAN="\033[38;2;80;220;235m"
C_GREEN="\033[38;2;80;250;160m"
C_RED="\033[38;2;255;85;85m"
C_YELLOW="\033[38;2;255;200;80m"
C_WHITE="\033[1;37m"
C_DIM="\033[38;5;243m"
C_RESET="\033[0m"

info()    { printf "  ${C_CYAN}▸${C_RESET} %s\n" "$1"; }
success() { printf "  ${C_GREEN}✔${C_RESET} %s\n" "$1"; }
error()   { printf "  ${C_RED}✖${C_RESET} %s\n" "$1"; }
warn()    { printf "  ${C_YELLOW}▲${C_RESET} %s\n" "$1"; }
header()  { printf "\n  ${C_CYAN}▎${C_RESET} ${C_WHITE}%s${C_RESET}\n\n" "$1"; }

# ─── Load config ─────────────────────────────────────────────────────────────
ENV_FILE="${SCRIPT_DIR}/demo.env"
if [[ ! -f "$ENV_FILE" ]]; then
  error "demo.env not found. Run setup.sh first."
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

# ─── Parse args ──────────────────────────────────────────────────────────────
NEW_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) NEW_VERSION="$2"; shift 2 ;;
    *) error "Unknown arg: $1"; exit 1 ;;
  esac
done

MODULE_CURRENT_VERSION="${MODULE_CURRENT_VERSION:?MODULE_CURRENT_VERSION is required}"
TFE_HOSTNAME="${TFE_HOSTNAME:-app.terraform.io}"
TFE_ORG="${TFE_ORG:?TFE_ORG is required}"
MODULE_NAME="${MODULE_NAME:-s3-bucket}"

# ─── Resolve source repo from PMR module ─────────────────────────────────────
# The source repo is the VCS-connected repo that TFC watches for tags
MODULE_SOURCE_REPO="${MODULE_SOURCE_REPO:-hashi-demo-lab/terraform-aws-s3-bucket}"
MODULE_SOURCE_BRANCH="${MODULE_SOURCE_BRANCH:-master}"

# ─── Auto-increment patch version if not specified ───────────────────────────
if [[ -z "$NEW_VERSION" ]]; then
  IFS='.' read -r major minor patch <<< "$MODULE_CURRENT_VERSION"
  NEW_VERSION="${major}.${minor}.$((patch + 1))"
fi

TAG_NAME="v${NEW_VERSION}"

# ─── Display config ──────────────────────────────────────────────────────────
header "Publish Module Version"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Source Repo" "$MODULE_SOURCE_REPO"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Source Branch" "$MODULE_SOURCE_BRANCH"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Current Version" "$MODULE_CURRENT_VERSION"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "New Version" "$NEW_VERSION"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Git Tag" "$TAG_NAME"
echo ""

# ─── Pre-flight checks ──────────────────────────────────────────────────────
header "Pre-flight Checks"

if [[ -z "${TFE_TOKEN:-}" ]]; then
  error "TFE_TOKEN environment variable is not set"
  exit 1
fi
success "TFE_TOKEN set"

if ! command -v gh &>/dev/null; then
  error "GitHub CLI (gh) is not installed"
  exit 1
fi
success "GitHub CLI available"

# Check if tag already exists on source repo
EXISTING_TAG=$(gh api "repos/${MODULE_SOURCE_REPO}/git/refs/tags/${TAG_NAME}" 2>/dev/null | jq -r '.ref // empty' 2>/dev/null || echo "")
if [[ -n "$EXISTING_TAG" ]]; then
  warn "Tag ${TAG_NAME} already exists on ${MODULE_SOURCE_REPO}"
  info "Skipping tag creation — checking if TFC has ingested it..."
else
  success "Tag ${TAG_NAME} does not exist yet"
fi

# ─── Create tag on source repo ──────────────────────────────────────────────
if [[ -z "$EXISTING_TAG" ]]; then
  header "Creating Tag"

  # Get the SHA of the latest commit on the source branch
  BRANCH_SHA=$(gh api "repos/${MODULE_SOURCE_REPO}/git/refs/heads/${MODULE_SOURCE_BRANCH}" \
    --jq '.object.sha' 2>/dev/null) || {
    error "Could not resolve HEAD of ${MODULE_SOURCE_REPO}@${MODULE_SOURCE_BRANCH}"
    error "Check that you have access to the repo and the branch exists"
    exit 1
  }
  info "Branch HEAD: ${BRANCH_SHA:0:12}"

  # Create a lightweight tag via the GitHub API
  TAG_RESULT=$(gh api "repos/${MODULE_SOURCE_REPO}/git/refs" \
    --method POST \
    --field "ref=refs/tags/${TAG_NAME}" \
    --field "sha=${BRANCH_SHA}" 2>&1) || {
    error "Failed to create tag:"
    echo "$TAG_RESULT"
    exit 1
  }

  CREATED_REF=$(echo "$TAG_RESULT" | jq -r '.ref // empty')
  if [[ "$CREATED_REF" == "refs/tags/${TAG_NAME}" ]]; then
    success "Tag created: ${TAG_NAME} → ${BRANCH_SHA:0:12}"
  else
    error "Unexpected response creating tag:"
    echo "$TAG_RESULT" | jq '.' 2>/dev/null || echo "$TAG_RESULT"
    exit 1
  fi
fi

# ─── Wait for TFC to ingest the new version ─────────────────────────────────
header "Waiting for TFC Ingestion"

info "TFC watches the source repo for new semver tags..."
info "Polling PMR for version ${NEW_VERSION} (timeout: 3 minutes)"

PMR_URL="https://${TFE_HOSTNAME}/api/v2/organizations/${TFE_ORG}/registry-modules/private/${TFE_ORG}/${MODULE_NAME}/aws/${NEW_VERSION}"
INGESTED=false

for i in $(seq 1 36); do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${TFE_TOKEN}" \
    "${PMR_URL}")

  if [[ "$HTTP_CODE" == "200" ]]; then
    # Verify status is ok (not pending/errored)
    VERSION_STATUS=$(curl -s \
      -H "Authorization: Bearer ${TFE_TOKEN}" \
      "${PMR_URL}" | jq -r '.data.attributes.status // "unknown"')

    if [[ "$VERSION_STATUS" == "ok" ]]; then
      INGESTED=true
      success "Version ${NEW_VERSION} is available in PMR (status: ok)"
      break
    elif [[ "$VERSION_STATUS" == "pending" ]]; then
      printf "\r  ${C_DIM}  Status: pending (attempt %d/36)${C_RESET}" "$i"
      sleep 5
    else
      warn "Version ${NEW_VERSION} exists but status is: ${VERSION_STATUS}"
      if [[ "$VERSION_STATUS" == "errored" ]]; then
        error "TFC failed to ingest version ${NEW_VERSION}"
        error "Check the module in the TFC registry for details"
        exit 1
      fi
      sleep 5
    fi
  else
    printf "\r  ${C_DIM}  Not found yet (attempt %d/36, HTTP %s)${C_RESET}" "$i" "$HTTP_CODE"
    sleep 5
  fi
done
echo ""

if [[ "$INGESTED" != true ]]; then
  error "Timed out waiting for TFC to ingest version ${NEW_VERSION}"
  info "The tag was created — TFC may still be processing it"
  info "Check: https://${TFE_HOSTNAME}/app/${TFE_ORG}/registry/modules/private/${TFE_ORG}/${MODULE_NAME}/aws"
  exit 1
fi

# ─── Update demo.env ────────────────────────────────────────────────────────
header "Updating demo.env"

if grep -q "^MODULE_TARGET_VERSION=" "$ENV_FILE"; then
  sed -i "s|^MODULE_TARGET_VERSION=.*|MODULE_TARGET_VERSION=\"${NEW_VERSION}\"|" "$ENV_FILE"
  success "Updated MODULE_TARGET_VERSION to ${NEW_VERSION}"
else
  echo "MODULE_TARGET_VERSION=\"${NEW_VERSION}\"" >> "$ENV_FILE"
  success "Added MODULE_TARGET_VERSION=${NEW_VERSION}"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
header "Module Version Published"

echo ""
printf "  ${C_WHITE}Version ${NEW_VERSION} is live in the private registry.${C_RESET}\n"
echo ""
printf "  ${C_WHITE}Next step:${C_RESET}\n"
printf "     ${C_DIM}bash specs/feat-consumer-uplift/demo/trigger-bump.sh${C_RESET}\n"
echo ""
