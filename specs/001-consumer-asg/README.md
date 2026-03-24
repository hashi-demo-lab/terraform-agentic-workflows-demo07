# 001-consumer-asg

## Purpose

This configuration deploys a sandbox Auto Scaling application stack in `ap-southeast-2` by composing private registry modules through HCP Terraform remote execution.

The deployment is intentionally small and development-focused:

- reuses the existing default VPC instead of creating new network infrastructure
- selects two default subnets in distinct Availability Zones
- prefers an internal HTTPS Application Load Balancer (ALB) reachable only from approved VPC CIDRs, with a documented sandbox-only internal HTTP fallback when no ACM certificate is available
- keeps EC2 instances private behind an instance security group
- runs a launch-template-backed Auto Scaling Group with bounded capacity
- creates CloudWatch alarms for ALB 5XX responses, healthy hosts, and ASG CPU utilization

## Implemented Files

The configuration created in checklist items A-D is organized as follows:

| File | Purpose |
|------|---------|
| `versions.tf` | Terraform and provider version requirements |
| `backend.tf` | HCP Terraform organization, hostname, project, and workspace selection |
| `providers.tf` | AWS provider configuration with `default_tags` and dynamic-credentials-compatible authentication |
| `variables.tf` | Deployment inputs and validation rules |
| `terraform.auto.tfvars.example` | Example non-secret values for required and optional inputs |
| `outputs.tf` | Deployment outputs for the ALB, Auto Scaling Group, launch template, and security groups |
| `data.tf` | Default VPC and subnet discovery |
| `locals.tf` | Shared tags, naming, subnet selection, and listener behavior |
| `main.tf` | Private registry module composition for ALB, security group, Auto Scaling, and CloudWatch alarms |

## Private Module Composition

This stack is module-first. It does not create raw AWS infrastructure resources in the consumer root.

| Logical Component | Source | Version | Purpose |
|------------------|--------|---------|---------|
| `module.alb` | `app.terraform.io/hashi-demos-apj/alb/aws` | `~> 10.1` | Internal ALB, listener, and target group with HTTPS preferred and a sandbox-only internal HTTP fallback |
| `module.instance_sg` | `app.terraform.io/hashi-demos-apj/security-group/aws` | `~> 5.3` | Instance security group allowing ingress only from the ALB |
| `module.autoscaling` | `app.terraform.io/hashi-demos-apj/autoscaling/aws` | `~> 9.0` | Launch-template-backed Auto Scaling Group with target tracking |
| `module.cloudwatch` | `app.terraform.io/hashi-demos-apj/cloudwatch/aws//wrappers/metric-alarm` | `~> 5.7` | Alarm-oriented monitoring for the sandbox deployment |

## Prerequisites

Before planning or applying this configuration, ensure the following are in place:

1. Access to the HCP Terraform organization `hashi-demos-apj`.
2. Access to the `sandbox` project and workspace `sandbox_consumer_asgterraform-agentic-workflows-demo07`.
3. The project-level variable set `agent_AWS_Dynamic_Creds` is attached to the workspace or inherited from the project.
4. The target AWS account has a default VPC in `ap-southeast-2` with at least two default subnets in distinct Availability Zones.
5. If you want HTTPS, you have an issued ACM certificate in `ap-southeast-2` for the DNS name clients will use to reach the internal ALB, or you know the `certificate_arn` to provide explicitly.
6. Required input values are provided for:
   - `owner`

Optional inputs include:

- `alb_ingress_cidrs` to narrow internal client ingress to the ALB beyond the default VPC CIDR
- `alarm_notification_arns` to send CloudWatch alarms to SNS topics
- `certificate_arn` to force a specific ACM certificate ARN instead of discovery
- `certificate_domain` to narrow automatic ACM discovery to a specific domain or wildcard name when HTTPS is available
- `image_id` to force a specific application AMI instead of Amazon Linux autodiscovery

## Required Workspace Settings

The configuration in `backend.tf` and `providers.tf` expects the workspace to use the following settings:

| Setting | Expected Value |
|---------|----------------|
| HCP Terraform hostname | `app.terraform.io` |
| Organization | `hashi-demos-apj` |
| Project | `sandbox` |
| Workspace | `sandbox_consumer_asgterraform-agentic-workflows-demo07` |
| Execution mode | Remote |
| Terraform version | `1.14.x` or another version satisfying `>= 1.14` |
| Auto apply | `false` |
| AWS authentication | Dynamic credentials from `agent_AWS_Dynamic_Creds` |
| Region | `ap-southeast-2` via `aws_region` input |

Workspace variables should supply, at minimum:

- `owner`

`certificate_arn` is optional. If it is set, Terraform keeps the ALB listener on HTTPS.

`certificate_domain` is also optional. When `certificate_arn = null` and `certificate_domain` is set, Terraform attempts ACM discovery for an `ISSUED` certificate in `ap-southeast-2`.

If both `certificate_arn` and `certificate_domain` are `null`, the configuration uses a sandbox-only internal HTTP listener fallback so the E2E run can proceed non-interactively in accounts where ACM certificates are unavailable.

`image_id` is also optional. If it is omitted or set to `null`, Terraform reads the AWS-managed Systems Manager public parameter for the latest regional Amazon Linux 2023 AMI and chooses the architecture that matches `instance_type`:

- `t3.micro` -> `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64`
- `t4g.micro` -> `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64`

Set `image_id` explicitly when you need an application-ready AMI that already serves `instance_port` and responds on `health_check_path`.

If you prefer CLI-driven remote runs, you can also start from `terraform.auto.tfvars.example` and provide values locally while still using the remote HCP Terraform backend.

## Apply Workflow

Run all commands from this directory:

```bash
cd specs/001-consumer-asg
```

1. Prepare input values.
    - Copy `terraform.auto.tfvars.example` to `terraform.auto.tfvars`, then update it with your sandbox values.
    - Set `certificate_arn` when you need an explicit certificate override.
    - Otherwise leave `certificate_arn = null` and set `certificate_domain` only when you want Terraform to discover a matching issued ACM certificate.
    - Leave both `certificate_arn = null` and `certificate_domain = null` for the sandbox-only internal HTTP fallback when no ACM certificate exists in `ap-southeast-2`.
    - Set `image_id` when you need to launch a specific application AMI.
    - Otherwise leave `image_id = null` so Terraform can auto-discover the latest Amazon Linux 2023 AMI for the selected `instance_type`.
    - Alternatively, set the same values as HCP Terraform workspace variables.
2. Initialize Terraform so the CLI connects to the remote workspace:

   ```bash
   terraform init
   ```

3. Confirm formatting and configuration validity:

   ```bash
   terraform fmt -check
   terraform validate
   ```

4. Review the proposed remote run:

   ```bash
   terraform plan
   ```

5. Apply the configuration in the sandbox workspace:

   ```bash
   terraform apply
   ```

6. After apply completes, review these outputs:
   - `alb_dns_name`
   - `alb_security_group_id`
   - `target_group_arn`
   - `autoscaling_group_name`
   - `launch_template_id`
   - `instance_security_group_id`

## Validation Commands

Use the following commands before opening a PR or starting a sandbox run:

```bash
cd specs/001-consumer-asg
terraform fmt -check
terraform validate
trivy config .
terraform plan
```

Notes:

- `terraform validate` checks syntax and internal references only.
- `trivy config .` should continue to pass because the fallback keeps the ALB internal and does not weaken instance network boundaries or introduce public exposure.
- `terraform plan` is the best validation for module access, workspace connectivity, and provider authentication.
- Because this stack uses remote execution, failures may indicate missing workspace permissions, missing dynamic credentials, or inaccessible private modules rather than HCL syntax problems.

## Sandbox Destroy Guidance

Destroy this deployment only from the same workspace and configuration directory used to create it:

```bash
cd specs/001-consumer-asg
terraform destroy
```

Before destroying:

1. Confirm you are targeting the sandbox workspace `sandbox_consumer_asgterraform-agentic-workflows-demo07`.
2. Confirm no shared validation activity is still using the ALB DNS name.
3. Review the destroy plan carefully.

Expected destroy behavior:

- The ALB, target group, instance security group, Auto Scaling Group, launch template, and CloudWatch alarms are removed.
- The default VPC and default subnets remain in place because they are discovered with data sources and are not managed by this configuration.
- Workspace settings and variable sets remain attached unless you remove them separately in HCP Terraform.

## Security and Operations Notes

- AWS credentials must come from HCP Terraform dynamic credentials, not static access keys.
- Provider-level `default_tags` apply `Application`, `ManagedBy`, `Environment`, `Project`, and `Owner`.
- Instances are not publicly exposed, and the ALB is configured as internal-only.
- HTTPS is enabled on the ALB listener when `certificate_arn` is provided or ACM discovery succeeds through `certificate_domain`.
- [SECURITY OVERRIDE] When both `certificate_arn` and `certificate_domain` are `null` in the sandbox project, the ALB falls back to an internal HTTP listener so non-interactive E2E validation can run in an account with no issued ACM certificates. This is acceptable only because traffic remains inside the default VPC, ALB ingress stays limited to approved CIDRs, and instances still accept inbound traffic only from the ALB security group.
- The Auto Scaling launch template uses `image_id` when provided or auto-discovers the latest Amazon Linux 2023 SSM public parameter for the selected instance architecture when `image_id = null`.
- When `alb_ingress_cidrs` is empty, the configuration allows ALB access only from the default VPC CIDR.
- Instance security-group egress is intentionally empty so application nodes do not initiate unrestricted outbound internet access.
- Sandbox capacity is intentionally constrained to `min_size = 1`, `desired_capacity = 1`, and `max_size = 2`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.37 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.37.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_alb"></a> [alb](#module\_alb) | app.terraform.io/hashi-demos-apj/alb/aws | ~> 10.1 |
| <a name="module_autoscaling"></a> [autoscaling](#module\_autoscaling) | app.terraform.io/hashi-demos-apj/autoscaling/aws | ~> 9.0 |
| <a name="module_cloudwatch"></a> [cloudwatch](#module\_cloudwatch) | app.terraform.io/hashi-demos-apj/cloudwatch/aws//wrappers/metric-alarm | ~> 5.7 |
| <a name="module_instance_sg"></a> [instance\_sg](#module\_instance\_sg) | app.terraform.io/hashi-demos-apj/security-group/aws | ~> 5.3 |

## Resources

| Name | Type |
|------|------|
| [aws_acm_certificate.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/acm_certificate) | data source |
| [aws_ssm_parameter.amazon_linux](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |
| [aws_subnet.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [aws_subnets.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |
| [aws_vpc.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarm_notification_arns"></a> [alarm\_notification\_arns](#input\_alarm\_notification\_arns) | Optional SNS topics notified by CloudWatch alarm actions. | `list(string)` | `[]` | no |
| <a name="input_alb_ingress_cidrs"></a> [alb\_ingress\_cidrs](#input\_alb\_ingress\_cidrs) | Optional IPv4 CIDR ranges allowed to reach the internal ALB listener. When empty, the default VPC CIDR is allowed. | `list(string)` | `[]` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for all provider and module operations. | `string` | `"ap-southeast-2"` | no |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | Optional ACM certificate ARN presented by the internal HTTPS ALB listener. When null, Terraform discovers a suitable issued certificate in the target region. | `string` | `null` | no |
| <a name="input_certificate_domain"></a> [certificate\_domain](#input\_certificate\_domain) | Optional ACM certificate domain to narrow automatic certificate discovery when certificate\_arn is not provided. | `string` | `null` | no |
| <a name="input_cpu_target_value"></a> [cpu\_target\_value](#input\_cpu\_target\_value) | Target CPU utilization percentage for target tracking scaling. | `number` | `60` | no |
| <a name="input_desired_capacity"></a> [desired\_capacity](#input\_desired\_capacity) | Steady-state instance count for development traffic. | `number` | `1` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment tag and environment-specific naming discriminator. | `string` | `"development"` | no |
| <a name="input_health_check_grace_period"></a> [health\_check\_grace\_period](#input\_health\_check\_grace\_period) | Warm-up period before ELB health checks affect replacement decisions. | `number` | `300` | no |
| <a name="input_health_check_path"></a> [health\_check\_path](#input\_health\_check\_path) | HTTP health-check path used by the load balancer target group. | `string` | `"/health"` | no |
| <a name="input_image_id"></a> [image\_id](#input\_image\_id) | Optional AMI ID override used by the launch template for application instances. When null, Terraform discovers the latest regional Amazon Linux 2023 AMI that matches the selected instance architecture. | `string` | `null` | no |
| <a name="input_instance_port"></a> [instance\_port](#input\_instance\_port) | Application port exposed by each instance and registered in the target group. | `number` | `80` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type for the Auto Scaling Group. | `string` | `"t3.micro"` | no |
| <a name="input_max_size"></a> [max\_size](#input\_max\_size) | Maximum burst capacity permitted in the sandbox environment. | `number` | `2` | no |
| <a name="input_min_size"></a> [min\_size](#input\_min\_size) | Minimum instance count for the Auto Scaling Group. | `number` | `1` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Owner tag value for support and accountability. | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project tag value propagated through provider default tags. | `string` | `"sandbox"` | no |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | Canonical name prefix used for load balancer, Auto Scaling, and alarm naming. | `string` | `"consumer-asg"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | Internal DNS name of the application load balancer. |
| <a name="output_alb_security_group_id"></a> [alb\_security\_group\_id](#output\_alb\_security\_group\_id) | Security group attached to the internal ALB front door. |
| <a name="output_autoscaling_group_name"></a> [autoscaling\_group\_name](#output\_autoscaling\_group\_name) | Auto Scaling Group name for operations and monitoring. |
| <a name="output_instance_security_group_id"></a> [instance\_security\_group\_id](#output\_instance\_security\_group\_id) | Security group ID attached to application instances. |
| <a name="output_launch_template_id"></a> [launch\_template\_id](#output\_launch\_template\_id) | Launch template identifier created for the compute fleet. |
| <a name="output_target_group_arn"></a> [target\_group\_arn](#output\_target\_group\_arn) | Target group ARN used for application traffic registration. |
<!-- END_TF_DOCS -->
