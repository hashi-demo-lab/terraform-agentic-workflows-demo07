## Research: HCP Terraform consumer deployment setup for org `hashi-demos-apj`, project `sandbox`, workspace `sandbox_consumer_serverlesterraform-agentic-workflows-demo07`

### Decision

Create a new CLI-driven HCP Terraform workspace in project `sandbox`, inherit the project-scoped `agent_AWS_Dynamic_Creds` variable set for AWS OIDC authentication, and deploy the existing development baseline that composes the private `lambda`, `dynamodb-table`, and `s3-bucket` modules; only `lambda_source_path` and `owner` must be supplied at run time for the `ap-southeast-2` development profile.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/lambda/aws` v8.1.2
  - **Purpose**: Provisions the serverless compute tier, its execution role, and the CloudWatch log group used by the consumer deployment.
  - **Key Inputs**: `function_name`, `handler`, `runtime`, `source_path`, `memory_size`, `timeout`, `environment_variables`, `policy_statements`, `cloudwatch_logs_retention_in_days`
  - **Key Outputs**: `lambda_function_name` (`string`), `lambda_function_arn` (`string`), `lambda_function_invoke_arn` (`string`), `lambda_cloudwatch_log_group_name` (`string`)
  - **Secure Defaults**: Creates its own role, keeps CloudWatch logging enabled, and does not require static AWS credentials when run from HCP Terraform with dynamic credentials.
- **Supporting Modules**:
  - `app.terraform.io/hashi-demos-apj/dynamodb-table/aws` v5.2.0 — application data table; exported outputs used by Lambda are `dynamodb_table_id` (`string`) and `dynamodb_table_arn` (`string`)
  - `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0 — private versioned assets bucket; exported outputs used by Lambda are `s3_bucket_name` (`string`) and `s3_bucket_arn` (`string`)
  - `app.terraform.io/hashi-demos-apj/workspace/tfe` v0.0.2 — optional platform module for provisioning a workspace as code; not required by the consumer root itself
  - `app.terraform.io/hashi-demos-apj/variable-sets/tfe` v0.5.0 — optional platform module for creating and attaching HCP Terraform variable sets; not required by the consumer root itself
- **Glue Resources Needed**: `random_string` for globally unique S3 bucket naming; `terraform { cloud { ... } }` for workspace binding; no credential glue resources are needed because auth is inherited from the project variable set.
- **Wiring Considerations**:
  - The root module binds directly to HCP Terraform with:
    - `organization = "hashi-demos-apj"`
    - `workspaces.name = "sandbox_consumer_serverlesterraform-agentic-workflows-demo07"`
    - `workspaces.project = "sandbox"`
  - The AWS provider should only set `region = var.aws_region` and `default_tags`; it must not declare `access_key`, `secret_key`, `session_token`, or equivalent static credential variables.
  - Verified cross-module wiring from the existing serverless consumer implementation is:
    - `module.app_table.dynamodb_table_id` (`string`) → Lambda env var `TABLE_NAME`
    - `module.assets_bucket.s3_bucket_name` (`string`) → Lambda env var `ASSETS_BUCKET`
    - `module.app_table.dynamodb_table_arn` (`string`) → Lambda IAM policy resource list
    - `module.assets_bucket.s3_bucket_arn` (`string`) → Lambda IAM policy resource list
    - `module.lambda_function.lambda_function_name` (`string`) → deployment outputs / monitoring dimensions
    - `module.lambda_function.lambda_cloudwatch_log_group_name` (`string`) → deployment outputs / observability wiring
  - The development baseline fixes `aws_region = "ap-southeast-2"` and `environment = "development"`; changing either breaks alignment with the validated sibling deployment pattern.

### Rationale

Live HCP Terraform API inspection shows that organization `hashi-demos-apj` contains project `sandbox` with project ID `prj-QueMgU3LXgV2Ag7s`, default execution mode `remote`, and an attached project-scoped variable set named `agent_AWS_Dynamic_Creds`. The exact requested workspace `sandbox_consumer_serverlesterraform-agentic-workflows-demo07` does not currently exist, and a search for both the requested spelling and the likely sibling spelling (`serverlessterraform`) returns no `demo07` workspace. A sibling workspace, `sandbox_consumer_serverlessterraform-agentic-workflows-demo06`, does exist in the same project and is the best reference implementation for this deployment shape.

That sibling workspace is configured as a non-VCS, remote-execution workspace with Terraform `1.14.7`, `auto_apply = false`, and no workspace-specific variables. The workspace inherits the `agent_AWS_Dynamic_Creds` variable set from the `sandbox` project, and the varset contains:

- `TFC_AWS_PROVIDER_AUTH = true`
- `TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::855831148133:role/tfstacks-role`
- `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE = aws.workload.identity`

This confirms the expected dynamic-credentials pattern: HCP Terraform exchanges OIDC identity for short-lived AWS credentials during each run, so the consumer code only needs functional provider settings such as region and tags. Downloaded configuration for the sibling deployment further confirms the root module composition and required variables:

- `backend.tf` binds directly to the workspace via a `cloud {}` block
- `providers.tf` configures only `region` and `default_tags`
- `main.tf` consumes the private `lambda`, `dynamodb-table`, and `s3-bucket` modules
- `variables.tf` shows that only `lambda_source_path` and `owner` are required without defaults; other deployment inputs have safe development defaults, including `aws_region = "ap-southeast-2"`, `environment = "development"`, `project_name = "consumer-serverless"`, `lambda_runtime = "python3.12"`, and `lambda_timeout_seconds = 10`

The latest successful run in the sibling workspace passed only two run variables — `lambda_source_path = "./app"` and `owner = "platform-team"` — which is strong evidence that a new `demo07` workspace should be configured the same way. State-version outputs from that workspace also confirm the effective output types seen by downstream consumers: all exported app outputs used for wiring (`assets_bucket_arn`, `assets_bucket_name`, `dynamodb_table_arn`, `dynamodb_table_id`, `lambda_function_arn`, `lambda_function_invoke_arn`, `lambda_function_name`, `lambda_log_group_name`) resolve to `string`.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Reuse `sandbox_consumer_serverlessterraform-agentic-workflows-demo06` | Would mix state between demo environments and remove the isolation expected for a distinct `demo07` validation workspace. |
| Create a VCS-backed workspace | The validated sibling pattern is CLI-driven with `vcs_repo = null`; VCS-backed workspaces complicate automation and are unnecessary for this deployment flow. |
| Add static AWS credentials as workspace variables | Conflicts with the inherited `agent_AWS_Dynamic_Creds` OIDC pattern and violates the consumer constitution requirement for dynamic credentials. |
| Require per-workspace variable sets | The `sandbox` project already attaches `agent_AWS_Dynamic_Creds` at project scope, so duplicating the varset at workspace scope adds management overhead without benefit. |
| Manage the app workspace from inside the consumer root with `workspace/tfe` and `variable-sets/tfe` | Possible for platform bootstrap, but not appropriate for the normal consumer deployment path because the workload root should target an already-created workspace, not create its own execution environment mid-run. |

### Sources

- Live HCP Terraform API: project lookup for `hashi-demos-apj/sandbox` → `prj-QueMgU3LXgV2Ag7s`
- Live HCP Terraform API: exact workspace search for `sandbox_consumer_serverlesterraform-agentic-workflows-demo07` → not found
- Live HCP Terraform API: exact workspace search for `sandbox_consumer_serverlessterraform-agentic-workflows-demo07` → not found
- Live HCP Terraform API: sibling workspace `sandbox_consumer_serverlessterraform-agentic-workflows-demo06`
- Live HCP Terraform API: `sandbox` project variable set `agent_AWS_Dynamic_Creds` and its attached env vars
- Downloaded configuration version `cv-eJHaprKge41kagBw` from sibling workspace `demo06`:
  - `backend.tf`
  - `providers.tf`
  - `main.tf`
  - `variables.tf`
  - `locals.tf`
  - `outputs.tf`
  - vendored module output definitions under `.terraform/modules/`
- `/workspace/docs/index.html` — consumer constitution and HCP Terraform sandbox/dynamic-credentials guidance
- `app.terraform.io/hashi-demos-apj/lambda/aws` v8.1.2
- `app.terraform.io/hashi-demos-apj/dynamodb-table/aws` v5.2.0
- `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0
- `app.terraform.io/hashi-demos-apj/workspace/tfe` v0.0.2
- `app.terraform.io/hashi-demos-apj/variable-sets/tfe` v0.5.0
