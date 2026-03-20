## Research: Best-practice security and observability defaults for a low-cost development serverless AWS consumer stack composed from private Terraform registry modules

### Decision

Use the private `lambda`, `s3-bucket`, `dynamodb-table`, `cloudwatch`, and `iam` modules with explicit security-focused overrides where module defaults are permissive or unset, and treat the existing default VPC as a discovered dependency rather than a managed module; keep Lambda out of the VPC by default unless a later dependency requires private network access.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/lambda/aws` v8.1.2
  - **Purpose**: Provisions the application Lambda function, execution role, log group integration, trigger permissions, and optional VPC attachment.
  - **Key Inputs**: `runtime`, `handler`, `timeout`, `memory_size`, `environment_variables`, `policies`, `allowed_triggers`, `cloudwatch_logs_retention_in_days`, `cloudwatch_logs_kms_key_id`, `tracing_mode`, `vpc_subnet_ids`, `vpc_security_group_ids`
  - **Key Outputs**: `lambda_function_name` (`string`), `lambda_function_arn` (`string`), `lambda_role_arn` (`string`), `lambda_cloudwatch_log_group_name` (`string`)
  - **Secure Defaults**: `attach_cloudwatch_logs_policy = true`; role creation supported in-module; VPC attachment is optional instead of forced.
- **Supporting Modules**:
  - `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0 — static asset bucket; useful security controls include `block_public_acls = true`, `ignore_public_acls = true`, `block_public_policy = true`, `restrict_public_buckets = true`, `object_ownership = "BucketOwnerEnforced"`, plus explicit TLS/encryption settings.
  - `app.terraform.io/hashi-demos-apj/dynamodb-table/aws` v5.2.0 — application data table; defaults to `billing_mode = "PAY_PER_REQUEST"` for low-cost dev, but encryption and PITR must be explicitly enabled if desired.
  - `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/log-group` v5.7.2 — explicit log group control for retention, naming, and optional KMS encryption.
  - `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm` v5.7.2 — Lambda error/throttle/duration alarms using Lambda output values as dimensions.
  - `app.terraform.io/hashi-demos-apj/iam/aws//modules/iam-policy` v6.2.3 — create a narrow custom policy that scopes Lambda access to the specific S3 bucket ARN and DynamoDB table ARN.
  - `app.terraform.io/hashi-demos-apj/iam/aws//modules/iam-role` v6.2.3 — optional if the team wants the role owned outside the Lambda module or needs a formal permissions-boundary pattern.
  - `app.terraform.io/hashi-demos-apj/security-group/aws` v5.3.1 — optional only if Lambda must run inside the default VPC; create a dedicated SG instead of using the default SG.
  - `app.terraform.io/hashi-demos-apj/kms/aws` v4.1.1 — optional customer-managed KMS key module when compliance requires CMKs for S3, CloudWatch Logs, or DynamoDB instead of service-managed encryption.
- **Glue Resources Needed**:
  - None required for the baseline security/observability design.
  - If the implementation must reference the existing default VPC, use provider data sources (`aws_vpc` with `default = true` and `aws_subnets`) rather than managing the default VPC directly.
  - `random_string` is optional only if a deterministic unique bucket suffix is required; the S3 module can otherwise generate a unique name when `bucket` is omitted.
- **Wiring Considerations**:
  - `module.lambda.lambda_function_name` (`string`) feeds CloudWatch alarm `dimensions.FunctionName` directly.
  - `module.lambda.lambda_cloudwatch_log_group_name` (`string`) can feed CloudWatch log metric filters directly when explicit log-based alarms are desired.
  - `module.lambda.lambda_function_arn` (`string`) feeds API Gateway integration permissions and other invoke-permission relationships.
  - `module.lambda.lambda_role_arn` (`string`) is the principal to grant KMS decrypt/use rights to if a CMK is introduced later.
  - `module.s3.s3_bucket_id` (`string`) is the bucket name to pass to Lambda environment variables or application config.
  - `module.s3.s3_bucket_arn` (`string`) feeds IAM policy resource scoping for `s3:GetObject`, `s3:PutObject`, and `s3:ListBucket` statements.
  - `module.dynamodb.dynamodb_table_id` (`string`) is the table name to pass into Lambda configuration.
  - `module.dynamodb.dynamodb_table_arn` (`string`) feeds IAM policy resource scoping for table CRUD permissions.
  - If Lambda is ever attached to the default VPC, supply discovered subnet IDs as `list(string)` to `vpc_subnet_ids` and a dedicated `security_group_id` (`string`) from the private security-group module to `vpc_security_group_ids`.

### Rationale

Private registry coverage is sufficient for the security/observability baseline: Lambda (`hashi-demos-apj/lambda/aws`), S3 (`hashi-demos-apj/s3-bucket/aws`), DynamoDB (`hashi-demos-apj/dynamodb-table/aws`), CloudWatch (`hashi-demos-apj/cloudwatch/aws`), IAM (`hashi-demos-apj/iam/aws`), security groups (`hashi-demos-apj/security-group/aws`), and optional KMS (`hashi-demos-apj/kms/aws`) are all available. Public registry mirrors show these private modules are aligned to the widely used upstream `terraform-aws-modules/*` patterns, so their input/output conventions are stable and composable.

Security defaults require a few explicit overrides because some important controls are not enabled by default:

- **Encryption**
  - `dynamodb-table` ships with `server_side_encryption_enabled = false`, so encryption at rest must be explicitly enabled.
  - `s3-bucket` exposes `server_side_encryption_configuration`, but encryption behavior should be set explicitly rather than assumed.
  - `lambda` supports `cloudwatch_logs_kms_key_id`, but for a low-cost dev stack this should remain optional; service-managed encryption is usually sufficient unless compliance requires CMKs.
  - Recommendation: use AWS-managed/service-managed encryption by default for dev to minimize cost and operational overhead, and only add the private `kms` module if policy requires customer-managed keys.

- **S3 public access**
  - The private S3 module already defaults the four S3 Public Access Block controls to secure values: `block_public_acls`, `ignore_public_acls`, `block_public_policy`, and `restrict_public_buckets` are all `true`.
  - The module also defaults `object_ownership = "BucketOwnerEnforced"`, which disables ACL-based ownership ambiguity.
  - Two useful transport controls are **not** defaulted on: `attach_deny_insecure_transport_policy` and `attach_require_latest_tls_policy` both default to `false`, so they should be set to `true` explicitly.
  - For a private static asset bucket in development, also set `attach_public_policy = false` unless the design intentionally needs public website access.

- **IAM least privilege boundaries**
  - The Lambda module can create the execution role, but least privilege depends on what policy ARNs are attached.
  - The cleanest low-friction pattern is: create a custom policy with `iam//modules/iam-policy`, scope it to the exact S3 bucket ARN and DynamoDB table ARN, then pass that policy ARN into the Lambda module `policies` input.
  - If the team needs a stricter separation-of-duties or permissions-boundary model, use `iam//modules/iam-role` and pass the resulting role ARN into the Lambda module with `create_role = false`.
  - Do **not** rely on broad AWS managed policies for application access if the resource ARNs are known at plan time.

- **CloudWatch logging and alarms**
  - The Lambda module exposes `cloudwatch_logs_retention_in_days`, but leaves it unset by default. For low-cost dev, set a bounded retention period such as 14 or 30 days.
  - The private CloudWatch module examples show the correct composition pattern for Lambda alarms via `modules/metric-alarm` and log controls via `modules/log-group`.
  - Minimum recommended alarms for this stack: Lambda `Errors > 0`, `Throttles > 0`, and a duration alarm near the configured timeout; if log-derived application error patterns matter, add a log metric filter alarm as well.
  - `tracing_mode` is nullable in the Lambda module. For a development stack, enabling `tracing_mode = "Active"` is a reasonable default when debugging latency/invocation chains matters; if the absolute lowest cost is more important than trace visibility, leave it unset and rely on logs + metrics.

- **Default VPC assumptions**
  - The AWS provider marks `aws_default_vpc` as an advanced adopt-or-create resource with caveats; it should not be used just to “look up” the default VPC.
  - For this serverless stack, S3, DynamoDB, API Gateway, and Lambda do **not** require a VPC attachment to work. Keeping Lambda outside the VPC avoids ENI churn, avoids NAT-related cost/complexity, and reduces networking surface area.
  - Therefore the best default assumption for a low-cost development stack is: **discover** the default VPC only if another dependency later requires private networking; otherwise do not attach Lambda to it.
  - If Lambda must be attached later, use the existing default VPC subnets discovered by data sources and attach a dedicated security group from the private `security-group` module. Do not use the default security group as an application boundary.

There is no private API Gateway module surfaced by registry search (`api`, `api-gateway`, `apigateway`, `gateway` all returned no match). That means the security/observability baseline should focus on the private modules above and treat API Gateway integration as a downstream wiring concern rather than a module-selection driver for this research item.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Manage the default VPC using `aws_default_vpc` or the private `vpc/aws` module | The stack requirement is to use the existing default VPC, not create or adopt a new managed network boundary. Provider docs warn `aws_default_vpc` is an advanced adopt/create resource with caveats. |
| Attach Lambda to the default VPC by default | Unnecessary for S3/DynamoDB/API Gateway access, adds ENI/network complexity, and can introduce NAT/egress cost for a low-cost dev stack. |
| Use a customer-managed KMS key everywhere by default | Better for strict compliance, but unnecessary operational/cost overhead for a low-cost dev environment when AWS-managed encryption meets the requirement. |
| Rely only on Lambda module defaults for security | Important controls are unset or disabled by default: DynamoDB SSE is off, CloudWatch log retention is unset, and S3 TLS enforcement policies are off. Explicit overrides are needed. |
| Use public registry modules directly | Consumer constitution requires private registry modules first; public registry was used only to confirm patterns and upstream behavior. |

### Sources

- Private registry module details: `app.terraform.io/hashi-demos-apj/lambda/aws` v8.1.2
- Private registry module details: `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0
- Private registry module details: `app.terraform.io/hashi-demos-apj/dynamodb-table/aws` v5.2.0
- Private registry module details: `app.terraform.io/hashi-demos-apj/cloudwatch/aws` v5.7.2 and its `modules/log-group` / `modules/metric-alarm` usage examples
- Private registry module details: `app.terraform.io/hashi-demos-apj/iam/aws` v6.2.3
- Private registry module details: `app.terraform.io/hashi-demos-apj/security-group/aws` v5.3.1
- Private registry module details: `app.terraform.io/hashi-demos-apj/kms/aws` v4.1.1
- Public registry pattern references: `terraform-aws-modules/lambda/aws`, `s3-bucket/aws`, `dynamodb-table/aws`, `cloudwatch/aws`, `vpc/aws`, `iam/aws`, `security-group/aws`
- Terraform AWS provider docs: `aws_default_vpc`, `aws_vpc` data source, `aws_subnets` data source
