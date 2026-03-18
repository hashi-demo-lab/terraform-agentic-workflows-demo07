# User Notes

## Uncertainty
- The task result outcome body endpoints returned empty, so there may be additional detail (e.g., which specific policy failed, what the recommendations were) that we could not retrieve
- It is unclear whether the empty body response is due to permissions, the API not supporting body content for this task type, or the task integration simply not providing body content

## Needs Human Review
- The policy failure details: the outcome shows "Failed" with "Gated" severity but we lack specifics about which policy was violated
- Whether the cost difference of +$0.10 (from $31.54 to $31.64) is expected or concerning for this workspace

## Workarounds
- No MCP tool exists for fetching task stage or task result details -- had to use direct curl API calls with TFE_TOKEN
- This is a significant gap in the MCP terraform toolset for anyone needing to inspect run task results

## Suggestions
- A dedicated MCP tool for fetching run task results (e.g., `mcp__terraform__get_task_stage_details` or `mcp__terraform__get_run_task_results`) would eliminate the need for direct API calls
- The skill being evaluated should handle the full chain: run -> task stages -> task results -> outcomes in a single flow
