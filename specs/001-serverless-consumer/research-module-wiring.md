## Research: Module wiring patterns for a serverless AWS consumer stack composed from private registry modules

### Decision
Use the private `lambda`, `dynamodb-table`, `s3-bucket`, and `security-group` modules as the core wiring surface; keep Lambda **out of the default VPC unless it truly needs private network access**; and treat API Gateway and CloudWatch alarm composition as current private-registry gaps that should follow the public `apigateway-v2` and `cloudwatch` interface patterns.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/lambda/aws` v8.1.2
  - **Purpose**: Creates the Lambda function, its execution role, permissions, log group, package handling, and optional VPC attachment.
  - **Key Inputs**:
    - `function_name` (`string`)
    - `runtime` (`string`)
    - `source_path` (`any`)
    - `environment_variables` (`map(string)`)
    - `vpc_subnet_ids` (`list(string)`)
    - `vpc_security_group_ids` (`list(string)`)
    - `allowed_triggers` (`map(any)`)
    - `attach_network_policy` (`bool`)
    - `policy_statements` (`any`) when attaching S3/DynamoDB access to the execution role
  - **Key Outputs consumed downstream**:
    - `lambda_function_name` (`string`)
    - `lambda_function_invoke_arn` (`string`)
    - `lambda_function_arn_static` (`string`)
    - `lambda_cloudwatch_log_group_name` (`string`)
    - `lambda_cloudwatch_log_group_arn` (`string`)
    - `lambda_role_name` (`string`)
  - **Secure Defaults**: CloudWatch Logs policy is attached by default, log group creation permission is enabled by default, and Function URL creation is disabled by default.

- **Supporting Modules**:
  - `app.terraform.io/hashi-demos-apj/dynamodb-table/aws` v5.2.0 — DynamoDB table for application state.
    - **Important inputs**: `name` (`string`), `hash_key` (`string`), `attributes` (`list(map(string))`), `billing_mode` (`string`), `stream_enabled` (`bool`), `server_side_encryption_enabled` (`bool`), `point_in_time_recovery_enabled` (`bool`).
    - **Verified outputs**:
      - `dynamodb_table_id` (`string`) — table name
      - `dynamodb_table_arn` (`string`)
      - `dynamodb_table_stream_arn` (`string`, nullable/empty when streams disabled)
    - **Secure defaults caveat**: encryption at rest and PITR are **not** enabled by default; both must be set explicitly for production.
  - `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0 — S3 bucket for artifacts, uploads, or async payload storage.
    - **Important inputs**: `bucket` (`string`), `environment` (`string`, required), `versioning` (`map(string)`), `server_side_encryption_configuration` (`any`), `enable_eventbridge` (`bool`).
    - **Verified outputs**:
      - `s3_bucket_name` (`string`)
      - `s3_bucket_arn` (`string`)
      - `s3_bucket_bucket_regional_domain_name` (`string`)
      - `s3_bucket_eventbridge_enabled` (`bool`)
    - **Secure defaults**: public access block settings default to secure values and object ownership defaults to `BucketOwnerEnforced`.
    - **Secure defaults caveat**: deny-insecure-transport and deny-unencrypted-upload policies are available but **off by default**.
  - `app.terraform.io/hashi-demos-apj/security-group/aws` v5.3.1 — Dedicated Lambda security group when VPC attachment is required.
    - **Important inputs**: `vpc_id` (`string`), `ingress_with_cidr_blocks` (`list(map(string))`), `ingress_with_source_security_group_id` (`list(map(string))`), `egress_rules` (`list(string)`).
    - **Verified outputs**:
      - `security_group_id` (`string`)
      - `security_group_arn` (`string`)
      - `security_group_vpc_id` (`string`)
  - `app.terraform.io/hashi-demos-apj/vpc/aws` v6.5.0 — Optional only when you must adopt/manage an existing default VPC or create a dedicated VPC.
    - **Important inputs**: `manage_default_vpc` (`bool`), `create_vpc` (`bool`), `private_subnets` (`list(string)`), `intra_subnets` (`list(string)`).
    - **Verified outputs**:
      - `vpc_id` (`string`)
      - `private_subnets` (`list(string)`)
      - `intra_subnets` (`list(string)`)
      - `default_security_group_id` (`string`)
      - `default_vpc_id` (`string`)
      - `default_vpc_default_security_group_id` (`string`)
    - **Gap**: the module exposes default VPC IDs/security-group IDs, but **does not expose default subnet IDs**, so it cannot fully wire Lambda into an existing default VPC by itself.
  - `app.terraform.io/hashi-demos-apj/cloudwatch/aws` v5.7.2 — Private registry entry exists, but its root module behaves like an umbrella/examples module rather than a clean single-purpose consumer interface.
    - **Usable pattern from public reference**: Lambda alarms and log-group modules consume Lambda function names/log group names, and emit alarm/log-group ARNs.
  - `app.terraform.io/hashi-demos-apj/iam/aws` v6.2.3 — Private registry entry exists, but the root interface is broad and not obviously optimized for “one Lambda execution role” consumption.
    - **Practical pattern**: let the Lambda module create its own execution role unless your org publishes a narrower private IAM role wrapper.
  - **Missing private module**: no private API Gateway module was found in `hashi-demos-apj` for `api`, `gateway`, `apigateway`, or `serverless`.
    - **Reference pattern**: `terraform-aws-modules/apigateway-v2/aws` v6.1.0
    - **Reference outputs**:
      - `api_id` (`string`)
      - `api_endpoint` (`string`)
      - `api_execution_arn` (`string`)
      - `stage_execution_arn` (`string`)

- **Glue Resources Needed**:
  - None for standard output-to-input wiring.
  - If the stack must reuse the **existing default VPC**, you need **data lookups** for default subnet IDs because the private VPC module does not export them.
  - Optional glue only for naming uniqueness, not for service connectivity: `random_id` or `random_string`.

- **Wiring Considerations**:
  - **Storage → Lambda**
    - `module.dynamodb_table.dynamodb_table_arn` (`string`) → Lambda role policy resources (`list(string)` / JSON policy statements)
    - `module.dynamodb_table.dynamodb_table_id` (`string`) → `module.lambda.environment_variables["TABLE_NAME"]` (`string`)
    - `module.s3_bucket.s3_bucket_arn` (`string`) → Lambda role policy resources (`list(string)` / JSON policy statements)
    - `module.s3_bucket.s3_bucket_name` (`string`) → `module.lambda.environment_variables["BUCKET_NAME"]` (`string`)
  - **Lambda ↔ API Gateway**
    - `module.lambda.lambda_function_invoke_arn` (`string`) → API Gateway integration `uri` (`string`) in REST-style/provider pattern
    - `module.lambda.lambda_function_arn_static` (`string`) or function ARN → API Gateway v2 module `target` / route integration target (`string`) in public-module pattern
    - `module.api.api_execution_arn` (`string`) → `module.lambda.allowed_triggers[*].source_arn` (`string`)
  - **Lambda → CloudWatch**
    - `module.lambda.lambda_function_name` (`string`) → CloudWatch metric alarm dimensions `{ FunctionName = ... }` (`map(string)`)
    - `module.lambda.lambda_cloudwatch_log_group_name` (`string`) → CloudWatch log group/query/subscription inputs (`string`)
  - **VPC/SG → Lambda**
    - `module.vpc.private_subnets` or `module.vpc.intra_subnets` (`list(string)`) → `module.lambda.vpc_subnet_ids` (`list(string)`) — direct type match
    - `module.security_group.security_group_id` (`string`) → `module.lambda.vpc_security_group_ids` (`list(string)`) via single-item list wrapper: `[module.security_group.security_group_id]`
    - `module.vpc.default_security_group_id` (`string`) technically matches the element type for `vpc_security_group_ids`, but is a poor security default for shared serverless workloads

### Verified Wiring Map

| Source | Output Type | Target | Input Type | Compatibility | Notes |
|---|---|---|---|---|---|
| `module.dynamodb_table` | `dynamodb_table_id` = `string` | `module.lambda.environment_variables["TABLE_NAME"]` | `string` | Direct | No transform needed |
| `module.dynamodb_table` | `dynamodb_table_arn` = `string` | Lambda IAM policy statements | JSON/list of strings | Direct embed | Use for `dynamodb:GetItem`, `PutItem`, etc. |
| `module.dynamodb_table` | `dynamodb_table_stream_arn` = `string` | Lambda event mapping / stream permissions | `string` | Direct, conditional | Only when `stream_enabled = true` |
| `module.s3_bucket` | `s3_bucket_name` = `string` | `module.lambda.environment_variables["BUCKET_NAME"]` | `string` | Direct | No transform needed |
| `module.s3_bucket` | `s3_bucket_arn` = `string` | Lambda IAM policy statements | JSON/list of strings | Direct embed | Usually include both bucket ARN and `${arn}/*` |
| `module.vpc` | `private_subnets` / `intra_subnets` = `list(string)` | `module.lambda.vpc_subnet_ids` | `list(string)` | Direct | Best fit when Lambda truly needs VPC |
| `module.security_group` | `security_group_id` = `string` | `module.lambda.vpc_security_group_ids` | `list(string)` | Wrap in list | Use `[module.security_group.security_group_id]` |
| `module.lambda` | `lambda_function_name` = `string` | CloudWatch alarm `dimensions.FunctionName` | `string` inside `map(string)` | Direct | Standard Lambda alarm pattern |
| `module.lambda` | `lambda_cloudwatch_log_group_name` = `string` | CloudWatch log query/subscription inputs | `string` | Direct | Use when observability module expects log-group name |
| `module.lambda` | `lambda_function_invoke_arn` = `string` | API integration `uri` | `string` | Direct | Matches Terraform provider REST integration pattern |
| `module.api` (future/private wrapper) | `api_execution_arn` = `string` | `module.lambda.allowed_triggers[*].source_arn` | `string` | Direct | Reverse permission edge from API to Lambda |

### Dependency Order

1. **Optional network discovery/adoption**
   - If Lambda must run in VPC, first resolve the target VPC, subnet IDs, and a dedicated security group.
   - If reusing the existing default VPC, gather default subnet IDs before Lambda creation.
2. **State/storage layer**
   - Create S3 and DynamoDB first so their names/ARNs can be injected into Lambda environment variables and IAM policy statements.
3. **Execution layer**
   - Create Lambda after storage outputs and any VPC/SG inputs are available.
4. **Ingress layer**
   - Create API Gateway after Lambda exists, because the integration target is the Lambda ARN/invoke ARN.
5. **Invoke permissions**
   - Create the Lambda permission edge after API Gateway exposes `api_execution_arn`/`stage_execution_arn`.
6. **Observability layer**
   - Create alarms, subscriptions, and log-derived queries after Lambda/API identifiers exist.

### Rationale

The private registry is strong for the core serverless compute/storage modules but incomplete at the HTTP ingress and observability composition edges.

- **Private-module availability is good for Lambda, DynamoDB, S3, SG, and VPC**. The `hashi-demos-apj` org contains consumer-usable modules for `lambda`, `dynamodb-table`, `s3-bucket`, `security-group`, and `vpc`, with concrete input/output contracts.
- **There is no private API Gateway module**. Searches for `api`, `gateway`, `apigateway`, and `serverless` returned no private module in `hashi-demos-apj`, so a fully module-only consumer stack cannot currently satisfy the API Gateway requirement without either (a) publishing a private API wrapper, or (b) temporarily deviating from the private-registry-only model.
- **The public API Gateway v2 module provides the right future contract**. Its inputs accept either a Lambda integration target/URI and its outputs return `api_execution_arn`, which is exactly what the Lambda module needs for `allowed_triggers.source_arn`. That gives a clean, bidirectional contract for a future private wrapper.
- **Default VPC is an anti-pattern for this workload unless there is a private dependency**. API Gateway, DynamoDB, S3, and CloudWatch do not require Lambda ENIs inside a VPC. Attaching Lambda to the default VPC adds subnet/SG dependencies and often breaks internet egress because Lambda ENIs in public subnets do not receive public IPs. The private VPC module also does not provide default subnet IDs, so “use the existing default VPC” is not a clean module-to-module path.
- **A dedicated SG is safer than the default SG**. The lambda module expects `vpc_security_group_ids` as `list(string)`, which aligns cleanly with a dedicated `security-group` module output wrapped in a list. Reusing `default_security_group_id` is technically possible but weak from a least-privilege standpoint.
- **Observability is best anchored on Lambda-owned outputs**. The Lambda module already returns the function name and log group name, which are the two values CloudWatch alarm/log-group patterns typically consume.

### Pitfalls

1. **No private API Gateway module exists today**
   - This is the main catalog gap for the requested stack.
2. **Default VPC reuse is underspecified at the module boundary**
   - The private VPC module can manage the default VPC, but it does not expose default subnet IDs needed by `module.lambda.vpc_subnet_ids`.
3. **Lambda-in-default-VPC often breaks outbound internet**
   - Public/default subnets do not automatically give Lambda internet access; NAT or endpoints are still needed.
4. **DynamoDB security defaults are not production-safe by default**
   - `server_side_encryption_enabled` and `point_in_time_recovery_enabled` default to `false`.
5. **S3 transport/encryption enforcement is not fully on by default**
   - Enable explicit deny policies for insecure transport and unencrypted uploads.
6. **Lambda permission/versioning edge case**
   - The Lambda module warns that `allowed_triggers` against the current version can fail unless `publish = true` or `create_current_version_allowed_triggers = false` is set.
7. **CloudWatch and IAM private registry entries are umbrella-style**
   - They are better as pattern references than immediate root-module consumer dependencies unless the org standardizes narrower wrappers.

### Alternatives Considered

| Alternative | Why Not |
|---|---|
| Put Lambda in the existing default VPC by default | Unnecessary for API Gateway, DynamoDB, S3, and CloudWatch; introduces subnet/NAT/security-group complexity and weakens portability |
| Reuse the VPC module's `default_security_group_id` directly | Works technically, but it is a shared, blunt security boundary; dedicated SG wiring is clearer and safer |
| Use Lambda Function URL instead of API Gateway | Avoids the catalog gap, but does not meet the explicit Lambda/API Gateway stack requirement |
| Depend directly on the private `cloudwatch` and `iam` root modules for all observability/IAM concerns | Their registry surfaces are broad/umbrella-style and not as consumer-friendly as the concrete Lambda/S3/DynamoDB contracts |
| Build the stack from raw API Gateway resources immediately | Conflicts with the consumer constitution's private-registry-first model |

### Sources

- Private registry: `hashi-demos-apj/lambda/aws` v8.1.2
- Private registry: `hashi-demos-apj/dynamodb-table/aws` v5.2.0
- Private registry: `hashi-demos-apj/s3-bucket/aws` v6.0.0
- Private registry: `hashi-demos-apj/security-group/aws` v5.3.1
- Private registry: `hashi-demos-apj/vpc/aws` v6.5.0
- Private registry: `hashi-demos-apj/cloudwatch/aws` v5.7.2
- Private registry: `hashi-demos-apj/iam/aws` v6.2.3
- Private registry search results for `api`, `gateway`, `apigateway`, and `serverless` in org `hashi-demos-apj` (no matching private API Gateway module)
- Public registry: `terraform-aws-modules/apigateway-v2/aws` v6.1.0
- Public registry: `terraform-aws-modules/lambda/aws` v8.7.0 (VPC example and `allowed_triggers` pattern)
- Terraform AWS provider docs: `aws_lambda_function`
- Terraform AWS provider docs: `aws_api_gateway_integration`
- Terraform AWS provider docs: `aws_vpc` data source
- Terraform AWS provider docs: `aws_dynamodb_table`
- Terraform AWS provider docs: `aws_s3_bucket`
