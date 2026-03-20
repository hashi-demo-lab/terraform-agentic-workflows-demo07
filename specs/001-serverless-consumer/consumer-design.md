# Consumer Design: 001-serverless-consumer

**Branch**: feat/001-serverless-consumer
**Date**: 2026-03-20
**Status**: Draft
**Provider**: aws ~> 5.0
**Terraform**: >= 1.14
**HCP Terraform Org**: hashi-demos-apj

---

## Table of Contents

1. [Purpose & Requirements](#1-purpose--requirements)
2. [Module Selection & Architecture](#2-module-selection--architecture)
3. [Module Wiring](#3-module-wiring)
4. [Security Controls](#4-security-controls)
5. [Implementation Checklist](#5-implementation-checklist)
6. [Open Questions](#6-open-questions)

---

## 1. Purpose & Requirements

This deployment provisions a low-cost development serverless application stack in `ap-southeast-2` for non-interactive end-to-end consumer workflow validation. It gives the demo workload a callable application endpoint, serverless compute, durable application state, private object storage for static assets, and operational visibility so the sandbox HCP Terraform workflow can plan, apply, validate, and destroy the stack without manual decision points.

**Scope boundary**: This design excludes production hardening beyond development needs, custom domains and certificates, WAF or CloudFront, CI/CD artifact build pipelines, cross-account deployment, VPC-only/private service connectivity, multi-environment promotion, and any new network creation beyond discovery of the account's existing default VPC context.

### Requirements

**Functional requirements** -- what the deployment must provision:

- Provision a development-grade serverless application interface in `ap-southeast-2` that can receive HTTP requests and invoke the application workload.
- Provision serverless compute for the application logic and make its runtime artifact path configurable for non-interactive execution.
- Provision a durable key-value data store for application state used by the serverless workload.
- Provision private object storage for static assets used by the application workload.
- Provide CloudWatch-based logs and alarms for the running workload so failures and abnormal runtime behavior are observable in the sandbox environment.
- Enforce least-privilege access so the application workload can access only its own data store and asset bucket.
- Bind execution to HCP Terraform organization `hashi-demos-apj`, project `sandbox`, and workspace `sandbox_consumer_serverlesterraform-agentic-workflows-demo07` using remote execution.
- Reuse the account's existing default VPC context as discovered environment metadata and avoid creating a new VPC for the baseline design.

**Non-functional requirements** -- constraints like compliance, performance, availability, cost:

- The design must support a non-interactive end-to-end consumer workflow and avoid unresolved operator choices during implementation.
- Private registry modules must be used for all supported infrastructure capabilities, and any unavoidable gap must be explicitly documented.
- The deployment must use HCP Terraform dynamic AWS credentials and must not rely on static access keys or secrets.
- Defaults must prefer minimal development cost, including serverless-first services, on-demand billing where appropriate, and bounded log retention.
- The design must follow provider default tagging with `ManagedBy`, `Environment`, `Project`, and `Owner`.
- The deployment must be development-oriented rather than production HA; resilience features should be enabled only where they materially improve safety without undermining the low-cost goal.

---

## 2. Module Selection & Architecture

### Architectural Decisions

**HTTP ingress pattern**: Use a Lambda-backed API Gateway HTTP API for the public application interface, while keeping every catalog-supported workload component on private registry modules. *Rationale*: `research-private-modules.md` found no private API Gateway module in `hashi-demos-apj`, but it also confirmed HTTP API is the lowest-cost and simplest integration model for Lambda; `research-module-wiring.md` independently confirmed the same catalog gap and validated the HTTP API v2 wiring pattern. *Rejected*: REST API was rejected because it is higher cost and operationally heavier, and Lambda Function URLs were rejected because they do not satisfy the explicit API Gateway requirement.

**Network posture**: Discover the existing default VPC for environmental alignment, but keep the baseline Lambda deployment outside the VPC. *Rationale*: `research-private-modules.md`, `research-module-wiring.md`, and `research-security-observability.md` all concluded that API Gateway, DynamoDB, S3, and CloudWatch do not require Lambda ENIs in the default VPC and that attaching Lambda would add subnet, egress, and security-group complexity without value for this workload. *Rejected*: Attaching Lambda to the default VPC by default was rejected due to extra cost and complexity, and managing the default VPC as a first-class module was rejected because the requirement is reuse, not network re-authoring.

**IAM composition**: Let the private Lambda module create the execution role and attach resource-scoped inline policy statements derived from the S3 and DynamoDB module outputs. *Rationale*: `research-private-modules.md` showed the Lambda module already supports role creation plus narrow policy attachments, while `research-security-observability.md` recommended least-privilege policies scoped to exact bucket and table ARNs; this keeps the module count low and the interface simple for a single consumer stack. *Rejected*: Broad AWS managed policies were rejected as over-permissive, and a separate private IAM role module was rejected as unnecessary extra wiring for a single Lambda workload.

**Cost-aware data and observability defaults**: Use pay-per-request DynamoDB, a private S3 bucket with explicit TLS and encryption controls, Lambda-managed CloudWatch logs with bounded retention, and a minimal Lambda alarm set. *Rationale*: `research-private-modules.md` recommended on-demand DynamoDB and arm64 Lambda for low-cost serverless workloads; `research-security-observability.md` identified the specific S3 and DynamoDB security settings that must be enabled explicitly and recommended a minimal alarm baseline of Lambda errors, throttles, and duration. *Rejected*: Provisioned DynamoDB throughput, public static website hosting, customer-managed KMS keys everywhere, and unbounded log retention were rejected because they increase cost or operational overhead for a development sandbox.

### Module Inventory

| Module | Registry Source | Version | Purpose | Conditional | Key Inputs | Key Outputs |
|--------|---------------|---------|---------|-------------|------------|-------------|
| lambda_function | app.terraform.io/hashi-demos-apj/lambda/aws | ~> 8.1 | Application compute, execution role, Lambda log group, and invoke permissions; selected from `research-private-modules.md` and validated against the existing sibling workspace pattern in `research-workspace-deployment.md`. | always | `function_name`, `source_path`, `handler`, `runtime`, `architectures`, `environment_variables`, `policy_statements`, `allowed_triggers`, `cloudwatch_logs_retention_in_days` | `lambda_function_name`, `lambda_function_arn`, `lambda_function_invoke_arn`, `lambda_cloudwatch_log_group_name` |
| app_table | app.terraform.io/hashi-demos-apj/dynamodb-table/aws | ~> 5.2 | Durable application state store; selected from `research-private-modules.md` with explicit encryption guidance from `research-security-observability.md`. | always | `name`, `hash_key`, `attributes`, `billing_mode`, `server_side_encryption_enabled`, `point_in_time_recovery_enabled` | `dynamodb_table_id`, `dynamodb_table_arn` |
| assets_bucket | app.terraform.io/hashi-demos-apj/s3-bucket/aws | ~> 6.0 | Private static-assets bucket with secure public-access defaults; selected from `research-private-modules.md` and hardened per `research-security-observability.md`. | always | `environment`, `bucket`, `versioning`, `server_side_encryption_configuration`, `attach_deny_insecure_transport_policy`, `attach_require_latest_tls_policy` | `s3_bucket_name`, `s3_bucket_arn`, `s3_bucket_bucket_regional_domain_name` |
| lambda_error_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | Alarm on Lambda invocation errors; selected from `research-private-modules.md` CloudWatch guidance and the minimum recommended alarm set in `research-security-observability.md`. | always | `alarm_name`, `namespace`, `metric_name`, `dimensions`, `comparison_operator`, `evaluation_periods`, `period`, `threshold`, `alarm_actions` | `alarm_arn` |
| lambda_throttle_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | Alarm on Lambda throttles to catch concurrency or permission issues; selected from `research-private-modules.md` and `research-security-observability.md`. | always | `alarm_name`, `namespace`, `metric_name`, `dimensions`, `comparison_operator`, `evaluation_periods`, `period`, `threshold`, `alarm_actions` | `alarm_arn` |
| lambda_duration_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | Alarm when execution duration approaches the configured timeout; selected from `research-security-observability.md` as a low-cost baseline safeguard. | always | `alarm_name`, `namespace`, `metric_name`, `dimensions`, `comparison_operator`, `evaluation_periods`, `period`, `threshold`, `alarm_actions` | `alarm_arn` |

### Glue Resources

| Resource Type | Logical Name | Purpose | Depends On |
|---------------|-------------|---------|------------|
| random_string | bucket_suffix | Provides deterministic uniqueness for the S3 bucket name while keeping the deployment reproducible across sandbox runs. | -- |

### Workspace Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| Organization | hashi-demos-apj | HCP Terraform organization |
| Project | sandbox | Existing HCP Terraform project validated by research |
| Workspace | sandbox_consumer_serverlesterraform-agentic-workflows-demo07 | Target sandbox workspace for remote execution |
| Execution Mode | Remote | Matches the validated sibling workspace pattern in `research-workspace-deployment.md` |
| Terraform Version | >= 1.14 | Aligns with constitution minimum and sibling workspace validation on Terraform 1.14.7 |
| Variable Sets | `agent_AWS_Dynamic_Creds` | Project-scoped dynamic AWS OIDC credentials variable set |
| VCS Connection | None | CLI-driven / non-VCS workspace pattern is the validated baseline |
| Deployment Region | ap-southeast-2 | Fixed development region for this design |

---

## 3. Module Wiring

### Wiring Diagram

```
random_string.bucket_suffix.result                  ──→ module.assets_bucket.bucket
module.app_table.dynamodb_table_id                 ──→ module.lambda_function.environment_variables["TABLE_NAME"]
module.app_table.dynamodb_table_arn                ──→ module.lambda_function.policy_statements["dynamodb"].resources
module.assets_bucket.s3_bucket_name                ──→ module.lambda_function.environment_variables["ASSETS_BUCKET"]
module.assets_bucket.s3_bucket_arn                 ──→ module.lambda_function.policy_statements["s3"].resources
module.lambda_function.lambda_function_invoke_arn  ──→ aws_apigatewayv2_integration.http_api.integration_uri [CONSTITUTION DEVIATION]
aws_apigatewayv2_stage.default.execution_arn       ──→ module.lambda_function.allowed_triggers["APIGateway"].source_arn [CONSTITUTION DEVIATION]
module.lambda_function.lambda_function_name        ──→ module.lambda_error_alarm.dimensions["FunctionName"]
module.lambda_function.lambda_function_name        ──→ module.lambda_throttle_alarm.dimensions["FunctionName"]
module.lambda_function.lambda_function_name        ──→ module.lambda_duration_alarm.dimensions["FunctionName"]
```

The existing default VPC is discovered in `data.tf` and surfaced as an informational output for environment alignment. No baseline module consumes it because the Lambda workload remains outside the VPC unless a future private dependency requires network attachment.

### Wiring Table

| Source Module | Output | Target Module | Input | Type | Transformation |
|--------------|--------|--------------|-------|------|----------------|
| `random_string.bucket_suffix` | `result` | `assets_bucket` | `bucket` | `string -> string` | `format("%s-%s-assets-%s", var.project_name, var.environment, random_string.bucket_suffix.result)` |
| `app_table` | `dynamodb_table_id` | `lambda_function` | `environment_variables["TABLE_NAME"]` | `string -> string` | direct |
| `app_table` | `dynamodb_table_arn` | `lambda_function` | `policy_statements["dynamodb"].resources` | `string -> list(string)` | `[module.app_table.dynamodb_table_arn, "${module.app_table.dynamodb_table_arn}/index/*"]` |
| `assets_bucket` | `s3_bucket_name` | `lambda_function` | `environment_variables["ASSETS_BUCKET"]` | `string -> string` | direct |
| `assets_bucket` | `s3_bucket_arn` | `lambda_function` | `policy_statements["s3"].resources` | `string -> list(string)` | `[module.assets_bucket.s3_bucket_arn, "${module.assets_bucket.s3_bucket_arn}/*"]` |
| `lambda_function` | `lambda_function_invoke_arn` | `aws_apigatewayv2_integration.http_api` | `integration_uri` | `string -> string` | direct |
| `aws_apigatewayv2_stage.default` | `execution_arn` | `lambda_function` | `allowed_triggers["APIGateway"].source_arn` | `string -> string` | `"${aws_apigatewayv2_stage.default.execution_arn}/*"` |
| `lambda_function` | `lambda_function_name` | `lambda_error_alarm` | `dimensions` | `string -> map(string)` | `{ FunctionName = module.lambda_function.lambda_function_name }` |
| `lambda_function` | `lambda_function_name` | `lambda_throttle_alarm` | `dimensions` | `string -> map(string)` | `{ FunctionName = module.lambda_function.lambda_function_name }` |
| `lambda_function` | `lambda_function_name` | `lambda_duration_alarm` | `dimensions` | `string -> map(string)` | `{ FunctionName = module.lambda_function.lambda_function_name }` |

### Provider Configuration

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        ManagedBy   = "terraform"
        Environment = var.environment
        Project     = var.project_name
        Owner       = var.owner
      },
      var.additional_tags
    )
  }

  # Dynamic credentials are supplied by the HCP Terraform
  # project variable set agent_AWS_Dynamic_Creds.
}
```

### Variables

| Variable | Type | Required | Default | Validation | Sensitive | Description |
|----------|------|----------|---------|------------|-----------|-------------|
| `aws_region` | `string` | No | `"ap-southeast-2"` | Must equal `ap-southeast-2` for this design. | No | AWS region used by the sandbox consumer deployment. |
| `environment` | `string` | No | `"dev"` | Must be one of `dev`, `staging`, or `prod`; the sandbox default is `dev`. | No | Environment tag and naming suffix for the sandbox deployment. |
| `project_name` | `string` | No | `"consumer-serverless"` | Must be 3-32 characters of lowercase letters, numbers, or hyphens. | No | Canonical project label used for tags and generated resource names. |
| `owner` | `string` | Yes | -- | Must be non-empty. | No | Owning team or person recorded in tags and operational metadata. |
| `lambda_source_path` | `string` | Yes | -- | Must be a non-empty relative or absolute path to the Lambda source package directory or artifact. | No | Filesystem path passed to the Lambda module for packaging or existing artifact reference. |
| `lambda_handler` | `string` | No | `"app.handler"` | Must contain a `.` separator in `file.function` form. | No | Handler entry point for the Lambda function. |
| `lambda_runtime` | `string` | No | `"python3.12"` | Must be one of the runtimes supported by the private Lambda module and the selected package. | No | Lambda runtime for the application function. |
| `lambda_architectures` | `list(string)` | No | `["arm64"]` | Values must be either `arm64` or `x86_64`. | No | Lambda CPU architecture list; `arm64` is the default cost-optimized choice. |
| `lambda_memory_mb` | `number` | No | `128` | Must be between `128` and `10240`. | No | Memory size for the Lambda function. |
| `lambda_timeout_seconds` | `number` | No | `10` | Must be between `3` and `30`. | No | Lambda timeout used for the development workload. |
| `lambda_log_retention_days` | `number` | No | `14` | Must be one of `7`, `14`, or `30`. | No | CloudWatch log retention period for the Lambda log group. |
| `dynamodb_hash_key` | `string` | No | `"id"` | Must be non-empty. | No | Partition key name for the application DynamoDB table. |
| `alarm_actions` | `list(string)` | No | `[]` | Every value must be a valid AWS ARN when supplied. | No | Optional alarm action ARNs, such as an SNS topic, attached to each CloudWatch alarm. |
| `additional_tags` | `map(string)` | No | `{}` | Keys must not override `ManagedBy`, `Environment`, `Project`, or `Owner`. | No | Extra organization-specific tags merged with the required provider default tags. |

### Outputs

| Output | Type | Source | Description |
|--------|------|--------|-------------|
| `api_invoke_url` | `string` | `aws_apigatewayv2_stage.default.invoke_url` | Invoke URL for the development HTTP API. |
| `lambda_function_name` | `string` | `module.lambda_function.lambda_function_name` | Name of the deployed Lambda function. |
| `lambda_function_arn` | `string` | `module.lambda_function.lambda_function_arn` | ARN of the deployed Lambda function. |
| `dynamodb_table_name` | `string` | `module.app_table.dynamodb_table_id` | Name of the application DynamoDB table. |
| `assets_bucket_name` | `string` | `module.assets_bucket.s3_bucket_name` | Name of the private S3 bucket storing application assets. |
| `lambda_log_group_name` | `string` | `module.lambda_function.lambda_cloudwatch_log_group_name` | CloudWatch Logs group name for the Lambda function. |
| `default_vpc_id` | `string` | `data.aws_vpc.default.id` | Identifier of the discovered existing default VPC in the target account. |

---

## 4. Security Controls

| Control | Enforcement | Module Config | Reference |
|---------|-------------|---------------|-----------|
| Encryption at rest | DynamoDB encryption is enabled explicitly, S3 default encryption is configured explicitly, and Lambda plus CloudWatch use AWS-managed service encryption without weakening defaults. | `app_table: server_side_encryption_enabled = true`; `assets_bucket: server_side_encryption_configuration = { rule = { apply_server_side_encryption_by_default = { sse_algorithm = "AES256" }}}`; `lambda_function: honour module defaults` | AWS Well-Architected Security Pillar — Data Protection at Rest; CIS AWS Foundations Benchmark — S3 default encryption |
| Encryption in transit | The application endpoint is exposed through HTTPS on API Gateway, and the S3 bucket denies insecure transport and requires modern TLS. | `assets_bucket: attach_deny_insecure_transport_policy = true, attach_require_latest_tls_policy = true`; API Gateway HTTP API TLS endpoint via provider-native resources | AWS Well-Architected Security Pillar — Data Protection in Transit; CIS AWS Foundations Benchmark — S3 secure transport |
| Public access | S3 public access blocks remain enabled, object ownership stays enforced, DynamoDB is private, and the only public surface is the required API Gateway endpoint. | `assets_bucket: block_public_acls = true, ignore_public_acls = true, block_public_policy = true, restrict_public_buckets = true, object_ownership = "BucketOwnerEnforced"`; `lambda_function: no function URL` | AWS Well-Architected Security Pillar — Infrastructure Protection; CIS AWS Foundations Benchmark — S3 public access block |
| IAM least privilege | The Lambda execution role is created by the private Lambda module and receives only table- and bucket-scoped permissions derived from workload-specific ARNs; AWS provider credentials come from HCP Terraform OIDC, not static keys. | `lambda_function: create_role = true, policy_statements = { dynamodb = { resources = [table ARN, table index ARNs] }, s3 = { resources = [bucket ARN, object ARN wildcard] } }`; workspace variable set `agent_AWS_Dynamic_Creds` | AWS Well-Architected Security Pillar — Identity and Access Management; CIS AWS Foundations Benchmark — temporary credentials / least privilege |
| Logging | Lambda logging remains enabled, log retention is explicitly bounded, and CloudWatch alarms are provisioned for errors, throttles, and near-timeout duration. | `lambda_function: attach_cloudwatch_logs_policy = true, cloudwatch_logs_retention_in_days = var.lambda_log_retention_days`; `lambda_error_alarm`, `lambda_throttle_alarm`, `lambda_duration_alarm` consume `module.lambda_function.lambda_function_name` | AWS Well-Architected Security Pillar — Logging and Monitoring; CIS AWS Foundations Benchmark — monitoring and alerting |
| Tagging | Required provider default tags propagate to all supported resources, and optional tags are merged without replacing mandatory governance tags. | `provider.aws.default_tags = { ManagedBy, Environment, Project, Owner }`; private modules receive tag propagation through provider defaults and explicit `tags` inputs where exposed | AWS Well-Architected Security Pillar — Traceability; AWS Well-Architected Operational Excellence — Operations as Code |

---

## 5. Implementation Checklist

- [x] **A: Platform scaffold** -- Create `versions.tf`, `backend.tf`, and `providers.tf` with Terraform/HCP Terraform version constraints, the `cloud {}` workspace binding for `sandbox_consumer_serverlesterraform-agentic-workflows-demo07`, and the AWS provider configuration using dynamic credentials and required `default_tags`.
- [x] **B: Interface scaffold** -- Create `variables.tf`, `locals.tf`, and `terraform.auto.tfvars.example` with the full deployment interface from Section 3, naming locals for resource names, and example values for the two required inputs.
- [x] **C: Core workload composition** -- Create `data.tf` and `main.tf` with default VPC discovery, `random_string.bucket_suffix`, the private `app_table`, `assets_bucket`, and `lambda_function` module calls, plus the provider-native API Gateway HTTP API integration required by the documented deviation.
- [x] **D: Observability and contract** -- Create `monitoring.tf` and `outputs.tf` with the three CloudWatch alarm module calls and all deployment outputs defined in Section 3.
- [x] **E: Documentation and validation** -- Create `README.md` describing usage, required workspace configuration, and the API Gateway deviation; then run `terraform fmt`, `terraform validate`, `tflint`, and `trivy config` without modifying any Terraform source files from earlier checklist items.

---

## 6. Open Questions

No deferred functional or non-functional questions remain for the baseline development design.

- [CONSTITUTION DEVIATION] **Constitution §1.1 / template constraint on glue resources**: Research in `research-private-modules.md` and `research-module-wiring.md` found no private API Gateway module in `hashi-demos-apj`, while the confirmed requirements explicitly require API Gateway integration. The implementation will therefore use the minimum provider-native `aws_apigatewayv2_*` resources needed to connect the private Lambda module to an HTTP API until the platform team publishes an approved private API Gateway wrapper. This deviation is justified because it preserves private-registry composition for all available catalog capabilities and keeps the non-module surface area limited to the exact integration gap.

---
