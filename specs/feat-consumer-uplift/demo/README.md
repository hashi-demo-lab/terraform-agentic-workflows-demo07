# Consumer Module Uplift — Demo Harness

Fully automated demo of the consumer module uplift pipeline. Creates a TFC workspace, deploys consumer code, and triggers Dependabot-style PRs that exercise every path of the pipeline.

## Prerequisites

- `gh` CLI authenticated to the target GitHub host
- `TFE_TOKEN` environment variable set (org-level or team token)
- `ANTHROPIC_API_KEY` available for GitHub Actions secrets
- Demo repo created via `create-demo-repos.zsh` and cloned locally
- You are inside the cloned demo repo

## Quick Start

```bash
# 1. Configure
cp specs/feat-consumer-uplift/demo/demo.env.example specs/feat-consumer-uplift/demo/demo.env
# Edit demo.env with your values

# 2. Setup (creates workspace, templates code, commits, creates labels)
bash specs/feat-consumer-uplift/demo/setup.sh

# 3. Add secrets to the GitHub repo (setup.sh prints the exact commands)
gh secret set TFE_TOKEN --repo <owner/repo>
gh secret set ANTHROPIC_API_KEY --repo <owner/repo>
gh secret set TFE_TOKEN_DEPENDABOT --repo <owner/repo>

# 4. Trigger the demo (creates Dependabot-style PR → pipeline runs)
bash specs/feat-consumer-uplift/demo/trigger-bump.sh

# 5. Watch the pipeline
# Open the Actions tab in the GitHub repo

# 6. Clean up
bash specs/feat-consumer-uplift/demo/teardown.sh
```

## Demo Scenarios

The trigger script supports 4 scenarios via `--scenario` flag or `DEMO_SCENARIO` in `demo.env`:

| Scenario | What Changes | Pipeline Path | Best For Showing |
|----------|-------------|---------------|-----------------|
| `patch` | Version constraint + tag | Classify → Validate (exit 2) → AI Analysis → Decision | Auto-merge for low-risk patches |
| `minor` | Version + logging config + new output | Classify → Validate (exit 2) → AI Analysis → Decision | Full AI analysis with config adaptation |
| `breaking` | Version + invalid output reference | Classify → Validate (exit 1) → Breaking label | Breaking change detection and blocking |
| `no-op` | Constraint format change only | Classify → Validate (exit 0) → PR auto-closed | No-change detection with explanation |

```bash
# Run specific scenario
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario breaking

# Run multiple scenarios (each creates a separate PR)
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario patch
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario minor
bash specs/feat-consumer-uplift/demo/trigger-bump.sh --scenario breaking
```

## What Each Script Does

### `setup.sh`
1. Reads config from `demo.env`
2. Resolves the TFC project ID via API
3. Creates a CLI-driven workspace in the sandbox project
4. Templates consumer Terraform code (s3-bucket module) into repo root
5. Creates GitHub labels for the pipeline (risk levels, decisions)
6. Commits and pushes to `main`
7. Prints secret configuration commands

### `trigger-bump.sh`
1. Creates a branch named `dependabot/terraform/<module>-<version>-<timestamp>`
2. Applies scenario-specific changes to the consumer code
3. Commits with Dependabot-style message
4. Pushes and creates a PR with `dependencies` + `terraform` labels
5. Pipeline auto-triggers on the PR

### `teardown.sh`
1. Closes all open demo PRs (branches matching `dependabot/terraform/`)
2. Deletes remote and local demo branches
3. Creates a destroy run in TFC (waits for completion)
4. Deletes the TFC workspace
5. Removes consumer `.tf` files from repo root

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `TFE_ORG` | `hashi-demos-apj` | HCP Terraform organization |
| `TFE_PROJECT` | `sandbox` | TFC project name |
| `TFE_HOSTNAME` | `app.terraform.io` | TFC hostname |
| `TFE_WORKSPACE` | (auto from repo name) | Workspace name |
| `GITHUB_REPO` | (auto from git remote) | GitHub repo (owner/name) |
| `MODULE_NAME` | `s3-bucket` | PMR module name |
| `MODULE_SOURCE` | `app.terraform.io/hashi-demos-apj/s3-bucket/aws` | Full module source |
| `MODULE_CURRENT_VERSION` | `5.8.2` | Starting version |
| `MODULE_TARGET_VERSION` | `5.8.2` | Version to bump to |
| `AWS_REGION` | `ap-southeast-2` | AWS region |
| `DEMO_SCENARIO` | `minor` | Default trigger scenario |

## Module Version Bumps

The PMR module (`s3-bucket`) currently has version `5.8.2`. The demo scenarios work with this single version by making config changes alongside the version constraint change, which produces meaningful `terraform plan` output.

For a **real version bump demo**:
1. Publish a new version of the module (e.g., tag `v5.9.0` on the source repo)
2. Update `MODULE_TARGET_VERSION` in `demo.env`
3. Run `trigger-bump.sh` — the pipeline will show actual interface diff via MCP

## Multi-Person Demo Setup

Each presenter gets their own demo repo via `create-demo-repos.zsh`:

```bash
# Creates demo01, demo02, etc. — each is a full clone with all branches
./create-demo-repos.zsh -t <template-number> -c 5

# Each presenter configures their own demo.env and runs setup.sh
# Workspaces are isolated (named after the repo)
# TFC project-level variables handle AWS credentials
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Pipeline doesn't trigger | Check branch name starts with `dependabot/terraform/` and PR changes `*.tf` files |
| `terraform init` fails | Verify `TFE_TOKEN` secret is set and workspace exists |
| Plan shows no changes | Expected for `no-op` scenario. For others, verify module source is correct |
| AI analysis job skipped | Only runs when plan exit code is 2 (changes detected) |
| Labels not created | Run `setup.sh` again or create manually via `gh label create` |
| Workspace delete fails | Resources may still exist; destroy via TFC UI first |
