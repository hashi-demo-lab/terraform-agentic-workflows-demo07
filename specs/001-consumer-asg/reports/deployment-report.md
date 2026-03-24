# Deployment Report: 001-consumer-asg
| Field | Value |
| --- | --- |
| Branch | 001-consumer-asg |
| Date | 2026-03-24 |
| Provider | aws ~> 6.37 |
| HCP Workspace | sandbox_consumer_asgterraform-agentic-workflows-demo07 |
## Modules Composed
| Module | Registry Source | Version | Status |
| --- | --- | --- | --- |
| alb | app.terraform.io/hashi-demos-apj/alb/aws | ~> 10.1 | PASS |
| instance_sg | app.terraform.io/hashi-demos-apj/security-group/aws | ~> 5.3 | PASS |
| autoscaling | app.terraform.io/hashi-demos-apj/autoscaling/aws | ~> 9.0 | PASS |
| cloudwatch | app.terraform.io/hashi-demos-apj/cloudwatch/aws//wrappers/metric-alarm | ~> 5.7 | PASS |
**Summary**: 4 private-registry modules composed, all version-pinned with `~>` constraints, and no raw `resource` blocks were found. One non-blocking design drift remains: `main.tf:129` uses the CloudWatch wrapper source while `consumer-design.md:76-79,148-151` documents the base module interface.
## Static Analysis
**pre-commit run --all-files**: PASS — Terraform fmt, validate, docs, tflint, trivy validation, EOF, YAML, large-file, merge-conflict, private-key, and Vault Radar hooks all passed.
## terraform validate
**Result**: CLEAN
## terraform fmt -check
**Result**: FORMATTED
## tflint
**Result**: CLEAN
## trivy config
| Metric | Count |
| --- | ---: |
| Total | 0 |
| Defects | 0 |
| Accepted | 0 |
## Run Tasks
**Total tasks**: 1 | Passed: 1 | Failed: 0 | Errored: 0
### Post-Plan Tasks
| Task Name | Status | Enforcement | Message | Link |
| --- | --- | --- | --- | --- |
| Apptio-Cloudability | passed | advisory | Total Cost before: 0.00, after: 31.84, diff: +31.84 | [Results](https://api.cloudability.com/governance/hcp/runtask/g_rwlFySlkI=) |
#### Apptio-Cloudability — Outcomes
| Outcome | Description | Status | Severity |
| --- | --- | --- | --- |
| Estimation | Cost Estimation Result | Passed | -- |
| Policy | Policy Evaluation Result | Passed | Advisory |
| Recommendation | Recommendation Result | Passed | -- |
### Key Findings
- Estimated monthly impact is **+$31.84 USD**, driven mostly by the ALB (**$31.54**) plus three CloudWatch alarms (**$0.30**).
- Cost estimation excluded `module.autoscaling.aws_autoscaling_group.this[0]`, so the monthly total is directionally useful but incomplete.
- Policy evaluation reported **10 advisory findings** for missing `cost-center` tags on ALB, listener, target group, security groups, launch template, and alarms; the task was advisory and did not block apply.
- No optimization recommendations were returned.
## Quality Score
| # | Dimension | Score | Issues |
| --- | --- | ---: | --- |
| 1 | Module Usage | 9.0 | 0 P0, 0 P1, 1 P2 |
| 2 | Security & Compliance | 8.0 | 0 P0, 1 P1, 0 P2 |
| 3 | Code Quality | 9.0 | 0 P0, 0 P1, 0 P2 |
| 4 | Variables & Outputs | 9.5 | 0 P0, 0 P1, 0 P2 |
| 5 | Wiring & Integration | 9.0 | 0 P0, 0 P1, 1 P2 |
| 6 | Constitution Alignment | 7.5 | 0 P0, 1 P1, 1 P2 |
**Overall Score**: 8.6/10.0 — Excellent
**Production Readiness**: Ready
## Sandbox Deployment
| Field | Value |
| --- | --- |
| Workspace | sandbox_consumer_asgterraform-agentic-workflows-demo07 |
| Run URL | https://app.terraform.io/app/hashi-demos-apj/workspaces/sandbox_consumer_asgterraform-agentic-workflows-demo07/runs/run-Box2g6mLRyzwEpSH |
| Run Status | applied |
| Plan Status | finished |
| Apply Status | applied |
| Resources Created | 14 |
| Resources Changed | 0 |
| Resources Destroyed | 0 |
| Cost Estimate | +31.84 USD/month (partial; ASG cost excluded by run task) |
## Sandbox Destroy
| Field | Value |
| --- | --- |
| Destroy Status | SKIPPED |
| Destroy Run URL | N/A |
## Overall Status
**PASS**
