## Research: Workspace and deployment

### Decision

Target HCP Terraform organization `hashi-demos-apj`, project `sandbox`, and workspace `sandbox_consumer_asgterraform-agentic-workflows-demo07`. Use remote execution and inherited dynamic AWS credentials. Do not use static AWS credentials.

### Workspace settings

| Setting | Value |
| --- | --- |
| Organization | `hashi-demos-apj` |
| Project | `sandbox` |
| Workspace | `sandbox_consumer_asgterraform-agentic-workflows-demo07` |
| Execution mode | `remote` |
| Auto-apply | `false` |
| Terraform version | `1.14.x` |
| Credentials | project-level dynamic AWS credentials |

### Discovered platform pattern

- The `sandbox` project exists and is valid.
- Comparable sandbox workspaces use remote execution.
- A project-level variable set named `agent_AWS_Dynamic_Creds` provides dynamic AWS auth.
- Region is not supplied by that variable set, so the consumer code should define `aws_region = "ap-southeast-2"` through Terraform configuration.

### Consumer requirements

- Use a `cloud {}` block in `backend.tf`.
- Configure the AWS provider in `providers.tf` with:
  - `region = var.aws_region`
  - `default_tags`
- Do not define `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`.
- Keep state in HCP Terraform only.

### Operational notes

- The requested workspace may need to be created if absent.
- Keep `auto_apply = false` to match sandbox norms and reduce risk.
- Prefer CLI-driven remote runs with HCP Terraform handling provider auth.
