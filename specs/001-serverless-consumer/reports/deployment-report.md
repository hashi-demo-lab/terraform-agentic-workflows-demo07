# Deployment Report: 001-serverless-consumer
| Field | Value |
| --- | --- |
| Branch | 001-serverless-consumer |
| Date | 2026-03-20 |
| Provider | hashicorp/aws ~> 6.13 (resolved 6.37.0) |
| HCP Workspace | sandbox_consumer_serverlesterraform-agentic-workflows-demo07 |
## Modules Composed
| Module | Registry Source | Version | Status |
| --- | --- | --- | --- |
| lambda_function | app.terraform.io/hashi-demos-apj/lambda/aws | ~> 8.1 | PASS |
| app_table | app.terraform.io/hashi-demos-apj/dynamodb-table/aws | ~> 5.2 | PASS |
| assets_bucket | app.terraform.io/hashi-demos-apj/s3-bucket/aws | ~> 6.0 | PASS |
| lambda_error_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | PASS |
| lambda_throttle_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | PASS |
| lambda_duration_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | PASS |
**Summary**: 6 inventory modules present; root also contains 4 provider-native `aws_apigatewayv2_*` resources plus `random_string`, with the deviation documented in design but not tagged in code with `[CONSTITUTION DEVIATION]`.
## terraform validate
**Result**: CLEAN
## terraform fmt -check
**Result**: FORMATTED
## tflint
**Result**: FINDINGS -- `main.tf:13` (`app_table`) and `main.tf:31` (`assets_bucket`) hit `aws_resource_missing_tags` for `Application` / `Environment` / `ManagedBy`.
## trivy config
| Metric | Count |
| --- | --- |
| Total | 20 |
| Defects | 20 |
| Accepted | 0 |
### Defects (block deployment)
| AVD-ID | Severity | File:Line | Description |
| --- | --- | --- | --- |
| AVD-DS-0002 / AVD-DS-0015 | HIGH | `.terraform/modules/lambda_function/examples/*/docker/Dockerfile` | 6 HIGH vendored-example Dockerfile findings (`root` user / missing `yum clean all`) |
| AVD-AWS-0024 / AVD-AWS-0001 | MEDIUM | `main.tf:9-25`, `main.tf:64-70` | DynamoDB PITR is not enabled and API Gateway stage access logging is absent |
| AVD-AWS-0089 | LOW | `main.tf:27-55` | S3 bucket access logging is not configured |
### Accepted Risks (do not block deployment)
None.
## Pre-commit
**Result**: PASS with skipped Terraform hooks; `terraform fmt`, `terraform validate`, `terraform docs`, `terraform tflint`, and `terraform validate with trivy` all showed `(no files to check) Skipped`, while EOF/YAML/large-files/merge-conflicts/private-keys/Vault-Radar passed.
## Run Tasks
**Total tasks**: 1 | Passed: 1 | Failed: 0 | Errored: 0
### Post-Plan Tasks
| Task Name | Status | Enforcement | Message |
| --- | --- | --- | --- |
| Apptio-Cloudability | passed | advisory | Total Cost before: 0.00, after: 3.18, diff: +3.18 |
**Outcomes**: Estimation = Passed; Policy = Passed (Advisory); Recommendation = Passed.
### Key Findings
**+$3.18/month** estimated cost (mostly S3 **$2.54**, Lambda **$0.19**, DynamoDB **$0.16**, and three alarms at **$0.10** each); policy reported **10 advisory `cost-center` tag findings**; no optimization recommendation was returned.
## Quality Score
| # | Dimension | Score | Issues |
| --- | --- | --- | --- |
| 1 | Module Usage | 7.0 | 1 P0 |
| 2 | Security & Compliance | 7.0 | 0 P0, 1 P1, 2 P2 |
| 3 | Code Quality | 7.5 | 0 P0, 0 P1, 2 P2 |
| 4 | Variables & Outputs | 9.5 | 0 P0, 0 P1, 0 P2 |
| 5 | Wiring & Integration | 9.0 | 0 P0, 0 P1, 0 P2 |
| 6 | Constitution Alignment | 6.0 | 1 P0, 0 P1, 1 P2 |
**Overall Score**: 7.4/10.0 — Good
**Production Readiness**: Not Ready
## Sandbox Deployment
| Field | Value |
| --- | --- |
| Workspace | sandbox_consumer_serverlesterraform-agentic-workflows-demo07 |
| Run URL | https://app.terraform.io/app/hashi-demos-apj/workspaces/sandbox_consumer_serverlesterraform-agentic-workflows-demo07/runs/run-YWh4PtLSK11TasGu |
| Plan Status | PLANNED |
| Apply Status | APPLIED |
| Resources Created | 37 |
| Resources Changed | 0 |
| Resources Destroyed | 0 |
| Cost Estimate | +3.18 USD/month |
## Sandbox Destroy
| Field | Value |
| --- | --- |
| Destroy Status | SKIPPED |
| Destroy Run URL | N/A |
## Overall Status
**FAIL** -- `tflint` is not clean, `trivy config .` contains blocking HIGH defects plus consumer-specific MEDIUM findings, DynamoDB PITR/API Gateway access logging are missing, and no destroy evidence was provided.
