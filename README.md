## Serverless Consumer Stack

This root module composes a development serverless application stack for the
`001-serverless-consumer` feature in AWS `ap-southeast-2`. It is designed for
non-interactive validation in HCP Terraform and provisions:

- a Lambda function for application compute
- a DynamoDB table for application state
- a private S3 bucket for application assets
- CloudWatch alarms for Lambda errors, throttles, and duration
- an API Gateway HTTP API endpoint for public ingress

The stack is module-first. DynamoDB, S3, Lambda, and CloudWatch alarms are
provisioned from private registry modules in
`app.terraform.io/hashi-demos-apj/...`.

## Private Registry Modules

This consumer composes the following private modules:

- `app.terraform.io/hashi-demos-apj/lambda/aws` `~> 8.1`
- `app.terraform.io/hashi-demos-apj/dynamodb-table/aws` `~> 5.2`
- `app.terraform.io/hashi-demos-apj/s3-bucket/aws` `~> 6.0`
- `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm`
  `~> 5.7`

## Required Workspace Configuration

This configuration is intended to run in HCP Terraform with the workspace
settings defined in `specs/001-serverless-consumer/consumer-design.md`.

| Setting | Required Value |
| --- | --- |
| Organization | `hashi-demos-apj` |
| Project | `sandbox` |
| Workspace | `sandbox_consumer_serverlesterraform-agentic-workflows-demo07` |
| Execution mode | `Remote` |
| Terraform version | `>= 1.14` |
| Variable set | `agent_AWS_Dynamic_Creds` |
| Region | `ap-southeast-2` |

Important notes:

- AWS credentials must come from the HCP Terraform dynamic credentials variable
  set `agent_AWS_Dynamic_Creds`.
- Do not configure static AWS access keys in Terraform variables, environment
  variables, or provider blocks.
- The workspace is designed for CLI-driven or non-VCS remote execution.

## Required Inputs

Two input variables must be provided:

- `owner`: owner or team recorded in required default tags
- `lambda_source_path`: path to the Lambda application source or artifact

An example input file is provided in `terraform.auto.tfvars.example`.

## Usage

1. Ensure the HCP Terraform workspace exists with the required organization,
   project, workspace name, and dynamic credentials variable set.
2. Copy the example variables file and adjust values as needed.
3. Initialize Terraform.
4. Run a plan or apply through the configured remote workspace.

Example:

```bash
cp terraform.auto.tfvars.example terraform.auto.tfvars
terraform init
terraform plan
```

## Outputs

Key outputs from this consumer include:

- `api_invoke_url`
- `lambda_function_name`
- `lambda_function_arn`
- `dynamodb_table_name`
- `assets_bucket_name`
- `lambda_log_group_name`
- `default_vpc_id`

## API Gateway Deviation

This stack intentionally uses provider-native API Gateway v2 resources instead
of a private registry module for ingress:

- `aws_apigatewayv2_api`
- `aws_apigatewayv2_stage`
- `aws_apigatewayv2_integration`
- `aws_apigatewayv2_route`

This is a documented design deviation, not an accidental departure from the
module-first pattern. Research for this feature found no private API Gateway
module in the `hashi-demos-apj` organization. API Gateway remains required by
the feature, so the HTTP API integration is implemented as glue code while all
other supported workload components continue to use private registry modules.

## Validation Commands

The checklist item for this feature requires the following validation commands:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
tflint
trivy config .
```

`terraform init -backend=false` is useful for local validation because the root
module is configured for an HCP Terraform `cloud {}` backend.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.13 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.7 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.37.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_app_table"></a> [app\_table](#module\_app\_table) | app.terraform.io/hashi-demos-apj/dynamodb-table/aws | ~> 5.2 |
| <a name="module_assets_bucket"></a> [assets\_bucket](#module\_assets\_bucket) | app.terraform.io/hashi-demos-apj/s3-bucket/aws | ~> 6.0 |
| <a name="module_lambda_duration_alarm"></a> [lambda\_duration\_alarm](#module\_lambda\_duration\_alarm) | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 |
| <a name="module_lambda_error_alarm"></a> [lambda\_error\_alarm](#module\_lambda\_error\_alarm) | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 |
| <a name="module_lambda_function"></a> [lambda\_function](#module\_lambda\_function) | app.terraform.io/hashi-demos-apj/lambda/aws | ~> 8.1 |
| <a name="module_lambda_throttle_alarm"></a> [lambda\_throttle\_alarm](#module\_lambda\_throttle\_alarm) | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 |

## Resources

| Name | Type |
|------|------|
| [aws_apigatewayv2_api.http_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api) | resource |
| [aws_apigatewayv2_integration.http_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_integration) | resource |
| [aws_apigatewayv2_route.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_route) | resource |
| [aws_apigatewayv2_stage.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_stage) | resource |
| [random_string.bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [aws_vpc.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_tags"></a> [additional\_tags](#input\_additional\_tags) | Extra organization-specific tags merged with the required provider default tags. | `map(string)` | `{}` | no |
| <a name="input_alarm_actions"></a> [alarm\_actions](#input\_alarm\_actions) | Optional alarm action ARNs, such as an SNS topic, attached to each CloudWatch alarm. | `list(string)` | `[]` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region used by the sandbox consumer deployment. | `string` | `"ap-southeast-2"` | no |
| <a name="input_dynamodb_hash_key"></a> [dynamodb\_hash\_key](#input\_dynamodb\_hash\_key) | Partition key name for the application DynamoDB table. | `string` | `"id"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment tag and naming suffix for the sandbox deployment. | `string` | `"dev"` | no |
| <a name="input_lambda_architectures"></a> [lambda\_architectures](#input\_lambda\_architectures) | Lambda CPU architecture list; arm64 is the default cost-optimized choice. | `list(string)` | <pre>[<br/>  "arm64"<br/>]</pre> | no |
| <a name="input_lambda_handler"></a> [lambda\_handler](#input\_lambda\_handler) | Handler entry point for the Lambda function. | `string` | `"app.handler"` | no |
| <a name="input_lambda_log_retention_days"></a> [lambda\_log\_retention\_days](#input\_lambda\_log\_retention\_days) | CloudWatch log retention period for the Lambda log group. | `number` | `14` | no |
| <a name="input_lambda_memory_mb"></a> [lambda\_memory\_mb](#input\_lambda\_memory\_mb) | Memory size for the Lambda function. | `number` | `128` | no |
| <a name="input_lambda_runtime"></a> [lambda\_runtime](#input\_lambda\_runtime) | Lambda runtime for the application function. | `string` | `"python3.12"` | no |
| <a name="input_lambda_source_path"></a> [lambda\_source\_path](#input\_lambda\_source\_path) | Filesystem path passed to the Lambda module for packaging or existing artifact reference. | `string` | n/a | yes |
| <a name="input_lambda_timeout_seconds"></a> [lambda\_timeout\_seconds](#input\_lambda\_timeout\_seconds) | Lambda timeout used for the development workload. | `number` | `10` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Owning team or person recorded in tags and operational metadata. | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Canonical project label used for tags and generated resource names. | `string` | `"consumer-serverless"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_invoke_url"></a> [api\_invoke\_url](#output\_api\_invoke\_url) | Invoke URL for the development HTTP API. |
| <a name="output_assets_bucket_name"></a> [assets\_bucket\_name](#output\_assets\_bucket\_name) | Name of the private S3 bucket storing application assets. |
| <a name="output_default_vpc_id"></a> [default\_vpc\_id](#output\_default\_vpc\_id) | Identifier of the discovered existing default VPC in the target account. |
| <a name="output_dynamodb_table_name"></a> [dynamodb\_table\_name](#output\_dynamodb\_table\_name) | Name of the application DynamoDB table. |
| <a name="output_lambda_function_arn"></a> [lambda\_function\_arn](#output\_lambda\_function\_arn) | ARN of the deployed Lambda function. |
| <a name="output_lambda_function_name"></a> [lambda\_function\_name](#output\_lambda\_function\_name) | Name of the deployed Lambda function. |
| <a name="output_lambda_log_group_name"></a> [lambda\_log\_group\_name](#output\_lambda\_log\_group\_name) | CloudWatch Logs group name for the Lambda function. |
<!-- END_TF_DOCS -->
