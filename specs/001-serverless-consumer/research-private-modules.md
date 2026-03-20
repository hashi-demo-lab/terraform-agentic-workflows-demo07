## Research: Private registry modules for a serverless AWS consumer stack in `hashi-demos-apj`

### Decision

Use the private `lambda`, `dynamodb-table`, `s3-bucket`, `cloudwatch`, and `iam` modules in `hashi-demos-apj` at their current viable private versions, and implement API Gateway HTTP API integration as thin Terraform glue because no private API Gateway module exists in the org.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/lambda/aws` v8.1.2
  - **Purpose**: Creates the Lambda function, its optional CloudWatch log group, and its execution role/policy attachments in one module.
  - **Best Fit For**: The application compute tier and most IAM wiring for a simple serverless consumer stack.
  - **Key Required Inputs**:
    - `function_name` (`string`)
    - `handler` (`string`) for Zip packages
    - `runtime` (`string`) for Zip packages
    - one of `source_path`, `local_existing_package`, `s3_existing_package`, or `image_uri`
  - **Important Optional Inputs**:
    - `create_role` (`bool`, default `true`)
    - `allowed_triggers` (`map(any)`) to create `aws_lambda_permission` entries, including API Gateway
    - `attach_policy_json`, `attach_policy_jsons`, `attach_policy`, `attach_policies`, `attach_policy_statements`
    - `cloudwatch_logs_retention_in_days` (`number`)
    - `logging_log_format` (`string`, default `"Text"`)
    - `architectures` (`list(string)`) for `arm64`
    - `vpc_subnet_ids` / `vpc_security_group_ids` only if VPC attachment is truly needed
  - **Key Outputs Used Cross-Module**:
    - `lambda_function_name` (`string`) — use for CloudWatch alarm dimensions and Lambda permissions
    - `lambda_function_arn` (`string`) — use where an ARN is required
    - `lambda_function_invoke_arn` (`string`) — use as API Gateway v2 integration URI
    - `lambda_cloudwatch_log_group_name` (`string`) — use if creating log metric filters or explicit log-group alarms
    - `lambda_cloudwatch_log_group_arn` (`string`) — use for access policies or log integrations
    - `lambda_role_arn` (`string`) — use if additional IAM attachments are managed separately
  - **Secure / Minimal-Cost Defaults**:
    - `create_role = true` avoids separate IAM module unless reuse is needed
    - `attach_cloudwatch_logs_policy = true` by default
    - Keep Lambda **out of the VPC** unless it must reach private resources; DynamoDB, S3, API Gateway, and CloudWatch do not require VPC attachment
    - Prefer `architectures = ["arm64"]` where runtime supports it for lower Lambda cost
    - Prefer `create_package = false` if artifacts are built externally in CI/CD

- **Supporting Module**: `app.terraform.io/hashi-demos-apj/dynamodb-table/aws` v5.2.0
  - **Purpose**: Creates the application DynamoDB table.
  - **Key Inputs**:
    - `name` (`string`)
    - `hash_key` (`string`)
    - `attributes` (`list(map(string))`)
    - optional `range_key` (`string`)
    - optional `billing_mode` (`string`, default `"PAY_PER_REQUEST"`)
    - optional `point_in_time_recovery_enabled` (`bool`, default `false`)
    - optional `stream_enabled` (`bool`, default `false`)
  - **Key Outputs Used Cross-Module**:
    - `dynamodb_table_id` (`string`) — table name/ID for app configuration and alarm dimensions
    - `dynamodb_table_arn` (`string`) — IAM policy resource target for Lambda access
    - `dynamodb_table_stream_arn` (`string`, only when streams enabled)
  - **Secure / Minimal-Cost Defaults**:
    - `billing_mode = "PAY_PER_REQUEST"` is the best fit for spiky/unknown workloads and avoids capacity planning
    - enable PITR only if recovery requirements justify cost
    - enable streams only if the workload actually consumes them

- **Supporting Module**: `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0
  - **Purpose**: Creates the static-assets bucket and enforces common S3 security controls.
  - **Key Inputs**:
    - `environment` (`string`, required by private module)
    - one of `bucket` (`string`) or `bucket_prefix` (`string`)
    - optional `cors_rule` (`any`) if browser uploads/downloads are required
    - optional `versioning` (`map(string)`)
    - optional `server_side_encryption_configuration` (`any`)
    - optional `policy` (`string`) + `attach_policy` (`bool`) when explicit bucket policy is needed
  - **Key Outputs Used Cross-Module**:
    - `s3_bucket_name` (`string`) — application config and IAM resource scoping
    - `s3_bucket_arn` (`string`) — IAM policy resource target
    - `s3_bucket_bucket_regional_domain_name` (`string`) — useful if later fronted by CloudFront
  - **Secure / Minimal-Cost Defaults**:
    - `block_public_acls = true`, `block_public_policy = true`, `ignore_public_acls = true`, `restrict_public_buckets = true` by default
    - `object_ownership = "BucketOwnerEnforced"` by default
    - `control_object_ownership = true` by default
    - `force_destroy = false` by default to avoid accidental data loss
    - for "static assets", prefer a **private bucket** unless direct website hosting is explicitly required

- **Supporting Module**: `app.terraform.io/hashi-demos-apj/cloudwatch/aws` v5.7.2
  - **Purpose**: Best used via submodules for explicit monitoring resources:
    - `//modules/log-group`
    - `//modules/metric-alarm`
    - `//modules/metric-alarms-by-multiple-dimensions`
    - `//modules/log-metric-filter`
  - **Best Fit For**:
    - Lambda error/throttle/duration alarms
    - API Gateway 4XX/5XX/latency alarms
    - explicit log groups when you do not want Lambda to manage them
  - **Key Inputs by Pattern**:
    - log group: `name`, `retention_in_days`
    - metric alarm: `alarm_name`, `namespace`, `metric_name`, `dimensions`, `comparison_operator`, `evaluation_periods`, `period`, `threshold`
    - multiple Lambda alarms: `dimensions = { key = { FunctionName = "..." } }`
  - **Important Outputs / Wiring**:
    - for Lambda alarms, the critical dimension value is `FunctionName = module.lambda.lambda_function_name`
    - for API Gateway alarms, use API/stage identifiers from API Gateway glue resources
  - **Secure / Minimal-Cost Defaults**:
    - prefer service metrics over custom metrics where possible
    - set `treat_missing_data = "notBreaching"` for sparse serverless workloads unless a missing metric should alarm

- **Supporting Module**: `app.terraform.io/hashi-demos-apj/iam/aws` v6.2.3
  - **Purpose**: Best used via submodules when IAM should be managed independently from the Lambda module:
    - `//modules/iam-role`
    - `//modules/iam-policy`
  - **Best Fit For**:
    - shared managed policies reused by multiple Lambdas
    - execution roles owned separately from the Lambda deployment module
    - stricter separation of duties
  - **Key Inputs by Pattern**:
    - iam role: `name`, trust policy inputs, `policies`
    - iam policy: `name`, `policy` JSON
  - **Important Outputs / Wiring**:
    - role ARN/name outputs are expected to be `string` values and can be passed to Lambda when `create_role = false`
  - **Secure / Minimal-Cost Defaults**:
    - prefer least-privilege managed policies scoped to specific S3 bucket and DynamoDB table ARNs
    - for this consumer stack, separate IAM module usage is optional because the Lambda module already supports role creation and multiple attachment methods

- **Private Registry Gap**:
  - No private API Gateway module was found in `hashi-demos-apj` for `api`, `api gateway`, or `serverless` queries.
  - The best-fit pattern is therefore:
    1. Use private Lambda module for the function and most IAM.
    2. Add thin API Gateway v2 glue resources in consumer code.
    3. Optionally standardize later on a private mirror of the public `terraform-aws-modules/apigateway-v2/aws` module if the org wants a registry-first API layer.

- **Glue Resources Needed**:
  - `aws_apigatewayv2_api`
  - `aws_apigatewayv2_integration`
  - `aws_apigatewayv2_route`
  - `aws_apigatewayv2_stage`
  - Lambda invoke permission, implemented by either:
    - `module.lambda.allowed_triggers`, or
    - explicit `aws_lambda_permission`
  - Optional data lookups only if needed:
    - `data "aws_vpc"` / `data "aws_subnets"` for the existing default VPC

- **Wiring Considerations**:
  - **Recommended API style**: use **HTTP API (API Gateway v2)**, not REST API, for lower cost and simpler Lambda proxy integration.
  - **Recommended network posture**: because this stack uses API Gateway, DynamoDB, S3, and CloudWatch, keep Lambda outside the VPC by default even though the account has a default VPC available.
  - **Primary typed cross-module wiring**:

    | Producer | Output | Verified HCL Type | Consumer | Purpose |
    |---|---|---:|---|---|
    | `module.lambda` | `lambda_function_invoke_arn` | `string` | `aws_apigatewayv2_integration.integration_uri` | HTTP API → Lambda proxy integration |
    | `module.lambda` | `lambda_function_name` | `string` | `aws_lambda_permission.function_name` or CloudWatch alarm dimensions | Lambda invoke permission and alarms |
    | `module.lambda` | `lambda_function_arn` | `string` | IAM policies / diagnostics / optional integrations | Full Lambda ARN consumers |
    | `module.lambda` | `lambda_cloudwatch_log_group_name` | `string` | CloudWatch log metric filter / log-group-based monitoring | Log monitoring |
    | `module.lambda` | `lambda_role_arn` | `string` | IAM extensions if role managed separately | Additional attachments |
    | `module.dynamodb_table` | `dynamodb_table_id` | `string` | app config / alarm dimensions / env vars | Table name/ID |
    | `module.dynamodb_table` | `dynamodb_table_arn` | `string` | Lambda IAM policy statements | Least-privilege table access |
    | `module.s3_bucket` | `s3_bucket_name` | `string` | app config / env vars / IAM policy conditions | Bucket name |
    | `module.s3_bucket` | `s3_bucket_arn` | `string` | Lambda IAM policy statements | Least-privilege bucket access |
    | `aws_apigatewayv2_stage` | `execution_arn` | `string` | Lambda permission `source_arn` | Restrict API Gateway invoke permission |
    | `aws_apigatewayv2_stage` | `invoke_url` | `string` | outputs / consumers | API endpoint |

  - **Minimal Lambda permission pattern**:

    ```hcl
    allowed_triggers = {
      APIGateway = {
        service    = "apigateway"
        source_arn = "${aws_apigatewayv2_stage.this.execution_arn}/*"
      }
    }
    ```

  - **Minimal IAM scope pattern**:
    - DynamoDB permissions scoped to `${module.dynamodb_table.dynamodb_table_arn}` and `${module.dynamodb_table.dynamodb_table_arn}/*` if indexes are used
    - S3 permissions scoped to `${module.s3_bucket.s3_bucket_arn}` and `${module.s3_bucket.s3_bucket_arn}/*`
  - **Monitoring pattern**:
    - Lambda alarms use namespace `AWS/Lambda` with dimension `FunctionName = module.lambda.lambda_function_name`
    - API Gateway alarms use `AWS/ApiGateway` or v2-compatible dimensions from the selected HTTP API resources

### Rationale

1. **Private registry coverage is strong for Lambda, DynamoDB, S3, CloudWatch, and IAM** in `hashi-demos-apj`, with these current private versions discovered:
   - `hashi-demos-apj/lambda/aws` v8.1.2
   - `hashi-demos-apj/dynamodb-table/aws` v5.2.0
   - `hashi-demos-apj/s3-bucket/aws` v6.0.0
   - `hashi-demos-apj/cloudwatch/aws` v5.7.2
   - `hashi-demos-apj/iam/aws` v6.2.3
2. **No private API Gateway module exists** in the org under relevant searches (`api gateway`, `api`, `serverless`), so API Gateway must currently be treated as glue.
3. The **private Lambda module is the best central module** because it already handles:
   - function packaging/deployment,
   - execution role creation,
   - policy attachment strategies,
   - CloudWatch log group integration,
   - trigger permission creation through `allowed_triggers`.
4. The **public module pattern** most aligned with the missing private capability is `terraform-aws-modules/apigateway-v2/aws` v6.1.0, which confirms the preferred HTTP API integration model and expected outputs such as `api_execution_arn`, `api_endpoint`, and stage log-group conventions.
5. **Type verification of cross-module outputs** was checked against the underlying AWS provider/resource attributes:
   - `aws_lambda_function.function_name`, `arn`, and `invoke_arn` are strings
   - `aws_cloudwatch_log_group.name` and `arn` are strings
   - `aws_dynamodb_table.id` and `arn` are strings
   - `aws_s3_bucket` bucket name/ARN outputs are strings
   - `aws_apigatewayv2_stage.execution_arn` and `invoke_url` are strings
6. **Default VPC usage is not required for the requested services**. Because API Gateway, DynamoDB, S3, and CloudWatch are managed AWS services, VPC-enabling the Lambda would add ENI/network complexity and possibly NAT cost without benefit for this specific stack.

### Alternatives Considered

| Alternative | Why Not |
|---|---|
| Add Lambda to the default VPC by default | Not needed for DynamoDB/S3/API Gateway/CloudWatch; increases complexity and can increase cost. |
| Use separate `iam/aws` role and policy submodules for the Lambda execution role from day one | Viable, but higher wiring overhead than the Lambda module's built-in role creation for a single consumer stack. |
| Use REST API Gateway instead of HTTP API Gateway | Higher cost and more moving parts for a simple Lambda-backed serverless consumer. |
| Use a public API Gateway module directly | Good pattern reference, but does not satisfy the org's private-registry-first preference. |
| Use raw S3 website hosting with a public bucket | Conflicts with secure bucket defaults and is a worse fit unless public website hosting is explicitly required. |

### Sources

- Private registry discovery in Terraform Cloud org `hashi-demos-apj`:
  - `app.terraform.io/hashi-demos-apj/lambda/aws` v8.1.2
  - `app.terraform.io/hashi-demos-apj/dynamodb-table/aws` v5.2.0
  - `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0
  - `app.terraform.io/hashi-demos-apj/cloudwatch/aws` v5.7.2
  - `app.terraform.io/hashi-demos-apj/iam/aws` v6.2.3
- Public registry pattern references:
  - `terraform-aws-modules/lambda/aws` v8.7.0
  - `terraform-aws-modules/dynamodb-table/aws` v5.5.0
  - `terraform-aws-modules/s3-bucket/aws` v5.11.0
  - `terraform-aws-modules/apigateway-v2/aws` v6.1.0
- AWS provider documentation references:
  - `aws_lambda_function`
  - `aws_lambda_permission`
  - `aws_apigatewayv2_integration`
  - `aws_apigatewayv2_route`
  - `aws_apigatewayv2_stage`
  - `aws_cloudwatch_log_group`
  - `aws_cloudwatch_metric_alarm`
  - `aws_dynamodb_table`
  - `aws_s3_bucket`
  - `aws_iam_role`
