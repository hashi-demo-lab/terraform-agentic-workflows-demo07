# v1 Improvements over v0

## Changes

1. **Added "save raw JSON" instruction** — v0 didn't explicitly tell the model to save the JSON artifact. Eval 0 asserts this but it was only passing by chance.

2. **Added edge case handling section** — Three distinct empty scenarios (no stages, stages with zero results, results with zero outcomes) are now explicitly documented with different user-facing messages. This directly addresses the eval 3 failure where the run had a task stage but zero results.

3. **Restructured presentation as three tiers** — Instead of one big example block, the output format is broken into Tier 1 (summary), Tier 2 (stage tables), Tier 3 (outcome sub-tables). This makes the format easier to follow and more consistent.

4. **Added "Highlighting problems" section** — Explicit guidance for errored/unreachable tasks, mandatory+failed blocking, and overridable stages.

5. **Streamlined field reference** — Removed `task_url` (rarely useful), condensed `permissions` and `is_overridable` into one line, simplified tags description.

6. **Improved error handling section** — Made each error type a separate bullet with actionable guidance instead of passive descriptions.

## Expected Impact

- Eval 3 should now pass (edge case handling for stages-with-zero-results)
- More consistent output formatting across different runs
- Better error communication
