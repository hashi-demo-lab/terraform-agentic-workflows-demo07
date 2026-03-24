## Research: Module wiring

### Decision

Compose `autoscaling`, `alb`, and `security-group` with AWS provider data sources for default VPC and subnet discovery. Use `cloudwatch` for alarms. Avoid raw AWS resources except provider data sources and locals-based glue.

### Required discovery

- `data "aws_vpc" "default"` with `default = true`
- `data "aws_subnets" "default"` filtered by the default VPC
- `data "aws_subnet"` for each selected subnet to make a deterministic two-AZ selection

### Recommended flow

1. Discover the default VPC.
2. Select two default subnets across distinct AZs in `ap-southeast-2`.
3. Create the ALB in those subnets.
4. Create an application SG allowing ingress only from the ALB SG on the app port.
5. Create the ASG across the same two subnets with a launch template.
6. Attach the ALB target group to the ASG through `traffic_source_attachments`.
7. Add CloudWatch alarms for ASG CPU, ALB 5XXs, and target group healthy hosts.

### Cross-module mapping

| Source | Target | Type handling |
| --- | --- | --- |
| `data.aws_vpc.default.id` | `module.alb.vpc_id` | direct |
| `data.aws_vpc.default.id` | `module.instance_sg.vpc_id` | direct |
| `local.selected_default_subnet_ids` | `module.alb.subnets` | direct |
| `local.selected_default_subnet_ids` | `module.autoscaling.vpc_zone_identifier` | direct |
| `module.alb.security_group_id` | instance SG ingress source SG | direct |
| `module.instance_sg.security_group_id` | `module.autoscaling.security_groups` | wrap in list |
| `module.alb.target_groups["app"].arn` | `module.autoscaling.traffic_source_attachments["app"].traffic_source_identifier` | direct |
| `module.autoscaling.autoscaling_group_name` | CloudWatch alarm dimensions | direct |
| `module.alb.arn_suffix` | CloudWatch ALB metrics | direct |

### Health and scaling

- Use `health_check_type = "ELB"` and set `health_check_grace_period`.
- Use a target group health endpoint such as `/health`.
- Baseline scaling policy:
  - target tracking on `ASGAverageCPUUtilization`
  - `min_size = 1`
  - `desired_capacity = 1`
  - `max_size = 2`

### Caveat

The private `cloudwatch` module clearly supports alarms. Dashboard support is not clearly documented in the private registry, so the design should either keep dashboards within a documented module capability or explicitly note the gap and use the nearest supported monitoring construct.
