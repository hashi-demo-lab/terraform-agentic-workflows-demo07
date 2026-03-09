# Consumer Module Uplift — Demo Harness

End-to-end demo of the consumer module uplift pipeline. Creates a TFC workspace, deploys consumer code, publishes a new module version, and triggers Dependabot-style PRs that exercise the AI-powered upgrade pipeline.

## Architecture

```
┌─────────────────────┐    tag vX.Y.Z     ┌──────────────────────────┐
│ Source Module Repo   │ ──────────────►   │  HCP Terraform PMR      │
│ (s3-bucket)          │   TFC ingests     │  s3-bucket/aws @ X.Y.Z  │
└─────────────────────┘                    └──────────────────────────┘
                                                      │
                                                      ▼
┌─────────────────────┐   PR triggers    ┌──────────────────────────┐
│ Demo Consumer Repo   │ ◄────────────── │  trigger-bump.sh creates │
│ (cloned template)    │   workflow       │  dependabot-style PR     │
└─────────────────────┘                  └──────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────────┐
│  terraform-consumer-uplift.yml                                    │
│  Classify → Validate → AI Analysis → Decision (merge/review/block)│
└───────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- `gh` CLI authenticated to the target GitHub host
- `TFE_TOKEN` environment variable set (org-level or team token)
- `ANTHROPIC_API_KEY` available for GitHub Actions secrets
- AWS credentials configured in the TFC project (variable set) for the sandbox workspace
- Demo repo created via `create-demo-repos.zsh` and cloned locally

## End-to-End Walkthrough

### Step 1: Create a demo repo from the template

```bash
# From the template repo root
./create-demo-repos.zsh -t <template-number> -c 1

# Clone the demo repo and cd into it
cd ~/Documents/repos/<demo-repo-name>
```

### Step 2: Configure

```bash
# Copy the example config
cp specs/feat-consumer-uplift/demo/demo.env.example specs/feat-consumer-uplift/demo/demo.env

# Edit demo.env — key settings:
#   BASE_BRANCH   → "feat/consumer-module-uplift" (current dev branch)
#                    Change to "main" once the workflow is merged
#   TFE_ORG       → your TFC org
#   TFE_PROJECT   → project with AWS credentials (variable set)
#   MODULE_SOURCE_REPO → GitHub repo backing the PMR module
```

### Step 3: Setup (workspace + consumer code)

```bash
bash specs/feat-consumer-uplift/demo/setup.sh
```

This creates:
- A TFC workspace (CLI-driven) in your sandbox project
- Consumer Terraform code (`.tf` files) committed to the base branch
- GitHub labels for the pipeline (risk levels, decisions)

If `terraform init/plan` fails (e.g. no AWS creds in workspace yet), that's OK — the workflow will handle it. Add `SKIP_PLAN=true` to skip.

### Step 4: Set GitHub secrets

```bash
gh secret set TFE_TOKEN --repo <owner/repo>
gh secret set ANTHROPIC_API_KEY --repo <owner/repo>
gh secret set TFE_TOKEN_DEPENDABOT --repo <owner/repo>
```

### Step 5: Publish a new module version to the PMR

**This is the critical gap step.** Before triggering a version bump PR, the target version must actually exist in the private registry.

This module uses **branch-based publishing** — the source repo (`hashi-demo-lab/terraform-aws-s3-bucket`) has a `pr_merge.yml` workflow that auto-publishes to the PMR when a PR is merged to `main` with a semver label.

The script drives this real pipeline end-to-end:

```bash
# Patch bump (default): 5.8.2 → 5.8.3
bash specs/feat-consumer-uplift/demo/publish-module-version.sh

# Minor bump: 5.8.2 → 5.9.0
bash specs/feat-consumer-uplift/demo/publish-module-version.sh --bump minor

# Major bump: 5.8.2 → 6.0.0
bash specs/feat-consumer-uplift/demo/publish-module-version.sh --bump major
```

The script:
1. Queries PMR for the current latest version
2. Creates a branch + trivial commit on the source module repo
3. Opens a PR with the `semver:patch/minor/major` label
4. Waits for validation CI, then merges the PR
5. Waits for `pr_merge.yml` to publish the new version to the PMR
6. Polls until TFC ingests the version (timeout: 6 min)
7. Updates `MODULE_TARGET_VERSION` in `demo.env`

### Step 6: Trigger the demo

```bash
# Uses default scenario from demo.env
bash specs/feat-consumer-uplift/demo/trigger-bump.sh

# Or pick a specific scenario
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario patch
```

This creates a PR with a `dependabot/terraform/` branch prefix, which triggers the consumer uplift workflow.

### Step 7: Watch the pipeline

Open the **Actions** tab in the GitHub repo to watch:
1. **Classify** — detects semver type from the diff
2. **Validate** — runs `terraform fmt/init/validate/plan`
3. **AI Analysis** — Claude analyzes the upgrade (if plan shows changes)
4. **Decision** — labels, comments, and optionally auto-merges

### Step 8: Clean up

```bash
bash specs/feat-consumer-uplift/demo/teardown.sh
```

This destroys infrastructure, deletes the workspace, closes PRs, removes demo branches, deletes the published demo version from the PMR, and removes consumer `.tf` files.

## Demo Scenarios

| Scenario | What Changes | Pipeline Path | Best For Showing |
|----------|-------------|---------------|-----------------|
| `patch` | Version constraint + tag | Classify → Validate (exit 2) → AI Analysis → Decision | Auto-merge for low-risk patches |
| `minor` | Version + logging config + new output | Classify → Validate (exit 2) → AI Analysis → Decision | Full AI analysis with config adaptation |
| `breaking` | Version + invalid output reference | Classify → Validate (exit 1) → Breaking label | Breaking change detection and blocking |
| `no-op` | Constraint format change only | Classify → Validate (exit 0) → PR auto-closed | No-change detection with explanation |

Run multiple scenarios (each creates a separate PR):
```bash
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario patch
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario minor
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario breaking
```

Note: For multiple scenarios, publish a new version between each if you want distinct version bumps, or they'll all reference the same target version.

## What Each Script Does

| Script | Purpose |
|--------|---------|
| `setup.sh` | Creates TFC workspace, templates consumer code, commits to base branch, creates labels |
| `publish-module-version.sh` | Creates PR on source repo → merges → CI publishes to PMR → updates `demo.env` |
| `trigger-bump.sh` | Creates a dependabot-style PR with scenario-specific changes → triggers pipeline |
| `teardown.sh` | Destroys infra, deletes workspace, closes PRs, cleans branches/tags/files |

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_BRANCH` | (auto-detect) | Branch with workflow files. Set to `feat/consumer-module-uplift` during dev |
| `TFE_ORG` | `hashi-demos-apj` | HCP Terraform organization |
| `TFE_PROJECT` | `sandbox` | TFC project name (should have AWS creds via variable set) |
| `TFE_HOSTNAME` | `app.terraform.io` | TFC hostname |
| `TFE_WORKSPACE` | (auto from repo name) | Workspace name |
| `GITHUB_REPO` | (auto from git remote) | GitHub repo (owner/name) |
| `MODULE_NAME` | `s3-bucket` | PMR module name |
| `MODULE_SOURCE` | `app.terraform.io/hashi-demos-apj/s3-bucket/aws` | Full module source |
| `MODULE_CURRENT_VERSION` | `5.8.2` | Starting version in consumer code |
| `MODULE_TARGET_VERSION` | `5.8.2` | Version to bump to (set by `publish-module-version.sh`) |
| `MODULE_SOURCE_REPO` | `hashi-demo-lab/terraform-aws-s3-bucket` | VCS repo backing the PMR module |
| `MODULE_SOURCE_BRANCH` | `master` | Branch to tag for new versions |
| `AWS_REGION` | `ap-southeast-2` | AWS region |
| `DEMO_SCENARIO` | `patch` | Default trigger scenario |

## Branch Awareness

This workflow currently lives on the `feat/consumer-module-uplift` branch. When testing:

- Set `BASE_BRANCH="feat/consumer-module-uplift"` in `demo.env`
- The demo repo (created from template) includes this branch
- PRs will be created against this branch, not `main`
- Once the workflow is merged to `main`, change `BASE_BRANCH` to `"main"`

## Multi-Person Demo Setup

Each presenter gets their own demo repo via `create-demo-repos.zsh`:

```bash
# Creates demo01, demo02, etc. — each is a full clone with all branches
./create-demo-repos.zsh -t <template-number> -c 5

# Each presenter configures their own demo.env and runs the walkthrough
# Workspaces are isolated (named after the repo)
# TFC project-level variable sets handle AWS credentials
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Pipeline doesn't trigger | Check branch name starts with `dependabot/terraform/` and PR changes `*.tf` files |
| `terraform init` fails | Verify `TFE_TOKEN` secret is set and workspace exists |
| Plan shows no changes | Expected for `no-op` scenario. For others, verify module version actually differs |
| AI analysis job skipped | Only runs when plan exit code is 2 (changes detected) |
| Labels not created | Run `setup.sh` again or create manually via `gh label create` |
| Workspace delete fails | Resources may still exist; destroy via TFC UI first |
| `trigger-bump.sh` refuses to run | `MODULE_TARGET_VERSION` must differ from `MODULE_CURRENT_VERSION` — run `publish-module-version.sh` first |
| Module version stuck in pending | Branch-based modules need TFC to clone the repo; check VCS connection in TFC |
| Wrong base branch for PR | Verify `BASE_BRANCH` in `demo.env` matches the branch with workflow files |
