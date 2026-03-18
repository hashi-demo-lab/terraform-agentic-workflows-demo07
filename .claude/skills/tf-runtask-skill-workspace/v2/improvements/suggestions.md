# v2 Improvements over v1

## Changes based on grader feedback

1. **Added Tier 4 — Actionable insights**: Graders flagged that no assertion checks the detail paragraphs (policy violations, cost recommendations) which contain the most actionable content. Added explicit guidance to synthesize key findings from outcome bodies in plain language, with a concrete example showing policy violations, cost impact, and recommendations.

2. **Explicit summary count display**: Graders noted ambiguity about whether "displayed" means in the raw JSON or the user-facing response. Added clarification that summary counts must appear in the user-facing text, even when all counts are zero.

3. **Tightened evals**:
   - Eval 0: Added assertion for actionable detail extraction (policy violations, cost recommendations)
   - Eval 0: Tightened script execution assertion to verify valid JSON output with run_id
   - Eval 0: Tightened JSON artifact assertion to verify file contains valid data
   - Eval 1: Tightened structured format assertion to check for specific column headers
   - Eval 3: Clarified summary counts must be in user-facing response text

## Expected Impact

- Richer, more actionable output that highlights what users need to act on
- More consistent summary display across all scenarios including edge cases
- Harder-to-game eval assertions that test substance, not just surface structure
