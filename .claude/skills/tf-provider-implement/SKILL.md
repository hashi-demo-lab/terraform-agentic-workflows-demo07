---
name: tf-provider-implement
description: SDD Phases 3-4 for provider development. TDD implementation and validation from an existing provider-design-{resource}.md.
user-invocable: true
argument-hint: "[feature-name] [resource-name] - Implement from existing specs/{feature}/provider-design-{resource}.md"
---

# SDD — Provider Implement

Builds and validates a Terraform provider resource from `specs/{FEATURE}/provider-design-{resource}.md` using TDD.

Post progress: `bash .foundations/scripts/bash/post-issue-progress.sh $ISSUE_NUMBER "<step>" "<status>" "<summary>"`
Checkpoint: `bash .foundations/scripts/bash/checkpoint-commit.sh --dir . --prefix feat "<step_name>"`

## Prerequisites

1. Resolve `$FEATURE` and `$RESOURCE` from `$ARGUMENTS` or current git branch name.
2. Verify `specs/{FEATURE}/provider-design-{resource}.md` exists via Glob. Stop if missing — tell user to run `/tf-provider-plan` first. Capture `$DESIGN_FILE`.
3. Find `$ISSUE_NUMBER` from `$ARGUMENTS` or `gh issue list --search "$FEATURE"`.

## Phase 3: Build + Test

4. Launch `tf-provider-test-writer` agent with `$DESIGN_FILE` to create test function stubs and config functions. Verify `_test.go` exists via Glob. Checkpoint commit.
5. Launch `tf-provider-developer` agent with `$DESIGN_FILE` for the first checklist item (typically "A: Schema & stubs") — creates resource file, model struct, empty CRUD methods, and test infrastructure (helpers, exports, sweep).
6. Run `go build -o /dev/null .` as the red TDD baseline. Checkpoint commit.
7. Extract remaining checklist items from design §6 via Grep (`- [ ]` lines).
8. For each remaining checklist item (sequentially):
   - Launch `tf-provider-developer` agent with `$DESIGN_FILE` and the specific checklist item.
   - Run `go build -o /dev/null .` and `go test -c -o /dev/null ./internal/service/<service>`.
   - Checkpoint commit.
9. After all items: `go build -o /dev/null .` + `go vet ./...`. If errors remain, re-launch `tf-provider-developer` targeted at specific errors (max 2 fix rounds).
10. Verify all checklist items in design §6 are marked `[x]` via Grep.

## Phase 4: Validate

11. Launch `tf-provider-validator` agent with `$DESIGN_FILE` and service directory. If auto-fixes applied, run `go build` to confirm.
12. If remaining issues, launch `tf-provider-developer` targeted at specific issues (max 2 fix rounds).
13. Run acceptance tests.
14. Write validation report to `specs/{FEATURE}/reports/` using the `tf-report-template` skill provider template.
15. Checkpoint commit, push branch, create PR linking to `$ISSUE_NUMBER`.

## Done

Report: build pass/fail, test compilation, acceptance test results (if run), validation status, PR link.
