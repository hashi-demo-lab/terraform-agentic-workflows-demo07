## Research: Security and cost defaults

### Decision

Use a public ALB only as the front door, keep instances non-public behind it, preserve module security defaults, and choose minimal development sizing.

### Security defaults

- Keep IMDSv2 required on the launch template.
- Keep EBS encryption enabled where supported by the module and AMI configuration.
- Do not expose EC2 instances directly to the internet.
- Restrict instance ingress to the ALB security group only.
- Prefer HTTPS listener support if the module inputs and available certificates allow it; otherwise document HTTP-only dev behavior as a temporary tradeoff.
- Enable available module logging and CloudWatch alarms without weakening security defaults.

### Cost-conscious defaults

- `min_size = 1`
- `desired_capacity = 1`
- `max_size = 2`
- Instance type baseline:
  - prefer `t4g.micro` if the AMI supports ARM
  - otherwise `t3.micro`
- Use conservative alarm thresholds and short retention where retention is configurable.
- Avoid new networking constructs such as NAT gateways or bespoke VPC resources.

### Monitoring

- ASG CPU utilization alarm
- ALB 5XX alarm
- Target group healthy host count alarm
- Dashboard-oriented observability should be included only through documented private-module capability

### Implementation guidance

- Use `health_check_type = "ELB"` for the ASG.
- Set `health_check_grace_period` explicitly.
- Use a target group health path such as `/health`.
- Keep IAM permissions narrow and rely on module defaults plus dynamic HCP Terraform credentials.
