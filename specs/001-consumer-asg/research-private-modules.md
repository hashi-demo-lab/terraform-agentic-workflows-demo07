## Research: Private modules

### Decision

Use private registry modules from `hashi-demos-apj` for `autoscaling`, `alb`, `security-group`, and `cloudwatch`. Do not use the private `vpc` module because this scenario must consume the existing default VPC rather than create networking.

### Recommended modules

| Purpose | Module | Version | Notes |
| --- | --- | --- | --- |
| Auto Scaling Group + launch template | `app.terraform.io/hashi-demos-apj/autoscaling/aws` | `~> 9.0` | Supports launch template creation, target tracking, and target group attachment. |
| Application Load Balancer | `app.terraform.io/hashi-demos-apj/alb/aws` | `~> 10.1` | Supports listeners, target groups, ALB SG, and subnet wiring. |
| Instance security group | `app.terraform.io/hashi-demos-apj/security-group/aws` | `~> 5.3` | Supports SG-to-SG ingress from the ALB. |
| Monitoring alarms | `app.terraform.io/hashi-demos-apj/cloudwatch/aws` | `~> 5.7` | Use alarm-oriented submodules. |

### Key inputs and outputs

- `autoscaling`
  - Inputs: `name`, `min_size`, `max_size`, `desired_capacity`, `image_id`, `instance_type`, `vpc_zone_identifier`, `security_groups`, `traffic_source_attachments`, `scaling_policies`, `health_check_type`, `health_check_grace_period`
  - Outputs: `autoscaling_group_name`, `autoscaling_group_arn`, `launch_template_id`
- `alb`
  - Inputs: `name`, `vpc_id`, `subnets`, `security_group_ingress_rules`, `listeners`, `target_groups`
  - Outputs: `security_group_id`, `dns_name`, `arn_suffix`, `target_groups`
- `security-group`
  - Inputs: `vpc_id`, `computed_ingress_with_source_security_group_id`, egress rules
  - Outputs: `security_group_id`

### Wiring notes

- Discover the default VPC and subnets with AWS data sources.
- Use exactly two default subnets in `ap-southeast-2`.
- Feed `module.alb.target_groups["app"].arn` into `module.autoscaling.traffic_source_attachments["app"].traffic_source_identifier`.
- Wrap `module.instance_sg.security_group_id` in a list for `module.autoscaling.security_groups`.
- Set the ALB target group `target_type = "instance"` and `create_attachment = false` so the ASG owns registration.

### Defaults to preserve

- `autoscaling` launch template defaults enforce IMDSv2.
- Keep module encryption and monitoring defaults unless there is a clear cost or policy reason to adjust them.
- Prefer CPU-based target tracking as the baseline. ALB request-count target tracking is possible but requires more derived labels.
