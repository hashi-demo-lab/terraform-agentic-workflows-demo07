# User Notes

## Uncertainty
- It is unknown whether `mcp__terraform__get_run_details` would include run task stage/result information in its response for a valid run. The nonexistent run ID prevented testing this.
- The MCP tool catalog may not be exhaustive -- there could be tools not yet discovered or registered.

## Needs Human Review
- Verify whether the Terraform MCP server is expected to have run task-specific endpoints, or if `get_run_details` is intended to be sufficient.
- Confirm whether run task results should be accessible through additional API calls that could be made via Bash/curl if API tokens are available.

## Workarounds
- No workarounds were available. Without a valid run ID and without dedicated run task tools, the request could not be fulfilled.
- A potential workaround would be to use `curl` against the Terraform Cloud API directly, but no API token or base URL was provided for direct API calls.

## Suggestions
- The skill should add dedicated handling for run task results, wrapping the Terraform Cloud API endpoints for task stages and task results.
- Error messages for nonexistent runs should be clear and actionable, suggesting the user verify the run ID.
- The skill could validate run ID format before making API calls.
