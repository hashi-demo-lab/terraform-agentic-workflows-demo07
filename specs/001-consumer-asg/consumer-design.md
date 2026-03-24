# Consumer Design: 001-consumer-asg

**Branch**: feat/001-consumer-asg
**Date**: 2026-03-24
**Status**: Approved
**Provider**: aws ~> 5.0
**Terraform**: >= 1.14
**HCP Terraform Org**: hashi-demos-apj
**HCP Terraform Project**: sandbox

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

This deployment provisions a development-grade web entry point and elastic compute tier for a sandbox application that needs to accept HTTP traffic, distribute requests across multiple Availability Zones, and scale within a small development capacity envelope. It exists to provide a non-interactive end-to-end consumer deployment in HCP Terraform that demonstrates private-registry module composition, remote execution, dynamic AWS credentials, and operational monitoring without introducing bespoke networking or unmanaged infrastructure patterns.

**Scope boundary**: This deployment excludes creation of a new VPC, NAT gateways, DNS records, ACM certificate lifecycle management, application build or release pipelines, operating system hardening beyond module defaults, database or stateful services, and any production-grade resilience features beyond the requested two-AZ development footprint.

### Requirements

**Functional requirements** -- what the deployment must provision:

- Provision an internet-reachable application entry point that distributes traffic across exactly two Availability Zones in `ap-southeast-2`.
- Provision an elastic compute fleet that maintains at least one healthy application instance and can scale out automatically when sustained load increases.
- Ensure replacement compute instances are created from a consistent instance configuration so that scaling and recovery behavior are deterministic.
- Route application traffic from the entry point to the compute fleet using load-balancer health checks, with unhealthy targets removed from service automatically.
- Publish CloudWatch-based operational monitoring for compute load, load balancer errors, and target health so a failed deployment state is observable.
- Deploy into the existing default VPC and reuse default subnets rather than creating bespoke networking infrastructure.
- Execute through the HCP Terraform workspace `sandbox_consumer_asgterraform-agentic-workflows-demo07` using remote execution and dynamic AWS credentials inherited from the project variable set.

**Non-functional requirements** -- constraints like compliance, performance, availability, cost:

- The deployment must remain in the `development` environment and use cost-conscious defaults appropriate for sandbox validation.
- Capacity must remain bounded to a small development footprint with a baseline of one instance and a maximum of two instances.
- The solution must preserve secure module defaults, avoid static AWS credentials, and prevent direct public exposure of compute instances.
- The deployment must tolerate a single-AZ failure at the load-balancer and subnet-selection layer by spanning two distinct Availability Zones in the default VPC.
- The configuration must be compatible with HCP Terraform remote execution and keep Terraform state only in HCP Terraform.
- The design must prefer documented private-registry module capabilities over custom resources or undocumented behaviors.

---

## 2. Module Selection & Architecture

### Architectural Decisions

**Reuse the existing default VPC**: The deployment will consume the default VPC and deterministically select two default subnets in distinct `ap-southeast-2` Availability Zones instead of creating new network infrastructure. *Rationale*: `research-private-modules.md` explicitly rejects the private VPC module because this scenario must reuse the existing default VPC, and `research-module-wiring.md` documents the required data-source pattern for default VPC and subnet discovery. *Rejected*: Creating a new VPC with private and public subnets was rejected because it violates the clarified scope, increases cost, and would add unnecessary networking constructs for a sandbox deployment.

**Expose only the load balancer publicly**: The application entry point will be a public ALB, while application instances remain reachable only from the ALB security group. *Rationale*: `research-security-cost.md` requires a public ALB as the front door, prohibits direct internet exposure of instances, and recommends SG-to-SG ingress restrictions; `research-private-modules.md` confirms the private `alb` and `security-group` modules support that pattern. *Rejected*: Public instance ingress or direct instance exposure was rejected because it weakens the security boundary and is unnecessary when the ALB already provides the internet-facing endpoint.

**Use launch-template-backed target tracking scaling with development bounds**: The compute tier will use an Auto Scaling Group with launch template creation, ELB health checks, and CPU-based target tracking constrained to `min_size = 1`, `desired_capacity = 1`, and `max_size = 2`. *Rationale*: `research-private-modules.md` confirms the private `autoscaling` module supports launch templates, target tracking, and target group attachment; `research-security-cost.md` and `research-module-wiring.md` recommend CPU target tracking plus explicit ELB health-check settings for the development footprint. *Rejected*: Fixed-capacity compute was rejected because it would not demonstrate scaling behavior, and request-count scaling was rejected because the research found CPU target tracking is the simpler documented baseline.

**Use CloudWatch alarms rather than undocumented dashboard features**: The observability layer will focus on alarm-driven monitoring for ASG CPU, ALB 5XX responses, and target-group healthy-host counts. *Rationale*: `research-private-modules.md` recommends the private `cloudwatch` module for alarm-oriented monitoring, and `research-module-wiring.md` notes that dashboard support is not clearly documented in the private registry, so the design should stay within confirmed alarm capabilities. *Rejected*: Custom CloudWatch resources or dashboard-first monitoring were rejected because they would either violate the module-first constitution or depend on undocumented module behavior.

**Run through HCP Terraform remote execution with dynamic credentials**: The deployment will execute in the `hashi-demos-apj` organization, `sandbox` project, and `sandbox_consumer_asgterraform-agentic-workflows-demo07` workspace using the `agent_AWS_Dynamic_Creds` variable set for AWS authentication. *Rationale*: `research-workspace-deployment.md` identifies remote execution, project-level dynamic AWS credentials, and the target workspace as the established platform pattern. *Rejected*: Local execution and static AWS credentials were rejected because they conflict with the workspace-aware and security-first constitution requirements.

### Module Inventory

Each selection below is taken directly from the private-registry research and aligned to the documented wiring pattern.

| Module | Registry Source | Version | Purpose | Conditional | Key Inputs | Key Outputs |
|--------|---------------|---------|---------|-------------|------------|-------------|
| alb | app.terraform.io/hashi-demos-apj/alb/aws | ~> 10.1 | Internet-facing application load balancer, listener, and instance target group (`research-private-modules.md`, `research-module-wiring.md`) | always | `name`, `vpc_id`, `subnets`, `security_group_ingress_rules`, `listeners`, `target_groups`, `tags` | `security_group_id`, `dns_name`, `arn_suffix`, `target_groups` |
| instance_sg | app.terraform.io/hashi-demos-apj/security-group/aws | ~> 5.3 | Least-privilege security group for application instances with ALB-sourced ingress (`research-private-modules.md`, `research-security-cost.md`) | always | `vpc_id`, `computed_ingress_with_source_security_group_id`, `egress_rules`, `tags` | `security_group_id` |
| autoscaling | app.terraform.io/hashi-demos-apj/autoscaling/aws | ~> 9.0 | Launch-template-backed Auto Scaling Group with target tracking and ALB attachment (`research-private-modules.md`, `research-security-cost.md`) | always | `name`, `min_size`, `max_size`, `desired_capacity`, `image_id`, `instance_type`, `vpc_zone_identifier`, `security_groups`, `traffic_source_attachments`, `scaling_policies`, `health_check_type`, `health_check_grace_period`, `tags` | `autoscaling_group_name`, `autoscaling_group_arn`, `launch_template_id` |
| cloudwatch | app.terraform.io/hashi-demos-apj/cloudwatch/aws | ~> 5.7 | Alarm-oriented CloudWatch monitoring for ASG CPU, ALB 5XX, and healthy host counts (`research-private-modules.md`, `research-module-wiring.md`) | always | `alarm_definitions`, `notification_arns`, `tags` | `alarm_names` |

### Glue Resources

| Resource Type | Logical Name | Purpose | Depends On |
|---------------|-------------|---------|------------|
| -- | -- | No glue resources are required. Default VPC discovery and two-AZ subnet selection are handled with AWS data sources and locals, which comply with the constitution without introducing raw infrastructure resources. | -- |

### Workspace Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| Organization | hashi-demos-apj | HCP Terraform organization from clarified requirements and `research-workspace-deployment.md` |
| Project | sandbox | Required target project from clarified requirements |
| Workspace | sandbox_consumer_asgterraform-agentic-workflows-demo07 | Remote execution target workspace |
| Execution Mode | Remote | HCP Terraform managed execution |
| Terraform Version | >= 1.14 | Matches constitution minimum and workspace research (`1.14.x`) |
| Variable Sets | agent_AWS_Dynamic_Creds | Project-level dynamic AWS credentials; no static keys |
| Auto Apply | false | Matches sandbox operating pattern from research |
| Region Handling | `aws_region = "ap-southeast-2"` | Region is configured in Terraform, not provided by the shared variable set |
| VCS Connection | Manual/CLI-driven remote runs | Research found remote runs are preferred even if the workspace must be created first |

---

## 3. Module Wiring

### Wiring Diagram

```text
data.aws_vpc.default.id ---------------------------> module.alb.vpc_id
data.aws_vpc.default.id ---------------------------> module.instance_sg.vpc_id
local.selected_default_subnet_ids -----------------> module.alb.subnets
local.selected_default_subnet_ids -----------------> module.autoscaling.vpc_zone_identifier
module.alb.security_group_id ----------------------> module.instance_sg.computed_ingress_with_source_security_group_id[0].source_security_group_id
module.instance_sg.security_group_id -------------> module.autoscaling.security_groups
module.alb.target_groups["app"].arn --------------> module.autoscaling.traffic_source_attachments["app"].traffic_source_identifier
module.autoscaling.autoscaling_group_name --------> module.cloudwatch.alarm_definitions["asg_cpu"].dimensions.AutoScalingGroupName
module.alb.arn_suffix ----------------------------> module.cloudwatch.alarm_definitions["alb_5xx"].dimensions.LoadBalancer
module.alb.target_groups["app"].arn_suffix -------> module.cloudwatch.alarm_definitions["healthy_hosts"].dimensions.TargetGroup
module.alb.arn_suffix ----------------------------> module.cloudwatch.alarm_definitions["healthy_hosts"].dimensions.LoadBalancer
```

### Wiring Table

| Source Module | Output | Target Module | Input | Type | Transformation |
|--------------|--------|--------------|-------|------|----------------|
| data.aws_vpc.default | `id` | alb | `vpc_id` | `string` | direct |
| data.aws_vpc.default | `id` | instance_sg | `vpc_id` | `string` | direct |
| local.selected_default_subnet_ids | `value` | alb | `subnets` | `list(string)` | direct |
| local.selected_default_subnet_ids | `value` | autoscaling | `vpc_zone_identifier` | `list(string)` | direct |
| alb | `security_group_id` | instance_sg | `computed_ingress_with_source_security_group_id[0].source_security_group_id` | `string` | direct |
| instance_sg | `security_group_id` | autoscaling | `security_groups` | `list(string)` | wrap in single-item list |
| alb | `target_groups["app"].arn` | autoscaling | `traffic_source_attachments["app"].traffic_source_identifier` | `string` | direct |
| autoscaling | `autoscaling_group_name` | cloudwatch | `alarm_definitions["asg_cpu"].dimensions.AutoScalingGroupName` | `string` | direct |
| alb | `arn_suffix` | cloudwatch | `alarm_definitions["alb_5xx"].dimensions.LoadBalancer` | `string` | direct |
| alb | `target_groups["app"].arn_suffix` | cloudwatch | `alarm_definitions["healthy_hosts"].dimensions.TargetGroup` | `string` | direct |
| alb | `arn_suffix` | cloudwatch | `alarm_definitions["healthy_hosts"].dimensions.LoadBalancer` | `string` | direct |

### Provider Configuration

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = var.environment
      Project     = var.project
      Owner       = var.owner
    }
  }

  # Authentication is supplied by HCP Terraform dynamic AWS credentials
  # from the project-level agent_AWS_Dynamic_Creds variable set.
}
```

### Variables

| Variable | Type | Required | Default | Validation | Sensitive | Description |
|----------|------|----------|---------|------------|-----------|-------------|
| `aws_region` | `string` | No | `"ap-southeast-2"` | Must equal `ap-southeast-2` for this deployment. | No | AWS region for all provider and module operations. |
| `environment` | `string` | No | `"development"` | Must equal `development`. | No | Environment tag and environment-specific naming discriminator. |
| `project` | `string` | No | `"sandbox"` | Must be non-empty. | No | Project tag value propagated through provider default tags. |
| `owner` | `string` | Yes | -- | Must be non-empty. | No | Owner tag value for support and accountability. |
| `service_name` | `string` | No | `"consumer-asg"` | Must match `^[a-z0-9-]+$`. | No | Canonical name prefix used for load balancer, Auto Scaling, and alarm naming. |
| `image_id` | `string` | Yes | -- | Must start with `ami-`. | No | AMI ID used by the launch template for application instances. |
| `instance_type` | `string` | No | `"t3.micro"` | Must be a permitted development instance family such as `t3.micro` or `t4g.micro`. | No | EC2 instance type for the Auto Scaling Group. |
| `instance_port` | `number` | No | `80` | Must be between `1` and `65535`. | No | Application port exposed by each instance and registered in the target group. |
| `health_check_path` | `string` | No | `"/health"` | Must start with `/`. | No | HTTP health-check path used by the load balancer target group. |
| `min_size` | `number` | No | `1` | Must be `>= 1` and `<= desired_capacity`. | No | Minimum instance count for the Auto Scaling Group. |
| `desired_capacity` | `number` | No | `1` | Must be `>= min_size` and `<= max_size`. | No | Steady-state instance count for development traffic. |
| `max_size` | `number` | No | `2` | Must be `>= desired_capacity` and `<= 2`. | No | Maximum burst capacity permitted in the sandbox environment. |
| `cpu_target_value` | `number` | No | `60` | Must be between `10` and `90`. | No | Target CPU utilization percentage for target tracking scaling. |
| `health_check_grace_period` | `number` | No | `300` | Must be between `0` and `900`. | No | Warm-up period before ELB health checks affect replacement decisions. |
| `alb_ingress_cidrs` | `list(string)` | No | `["0.0.0.0/0"]` | Every element must be a valid IPv4 CIDR. Public ingress is limited to the ALB listener only. | No | CIDR ranges allowed to reach the public ALB listener. |
| `certificate_arn` | `string` | No | `""` | Must be empty or start with `arn:aws:acm:`. | No | Optional ACM certificate ARN to enable HTTPS on the ALB listener for this deployment. |
| `alarm_notification_arns` | `list(string)` | No | `[]` | Each element must start with `arn:aws:sns:` when provided. | No | Optional SNS topics notified by CloudWatch alarm actions. |

### Outputs

| Output | Type | Source | Description |
|--------|------|--------|-------------|
| `alb_dns_name` | `string` | `module.alb.dns_name` | Public DNS name of the application load balancer. |
| `alb_security_group_id` | `string` | `module.alb.security_group_id` | Security group attached to the ALB front door. |
| `target_group_arn` | `string` | `module.alb.target_groups["app"].arn` | Target group ARN used for application traffic registration. |
| `autoscaling_group_name` | `string` | `module.autoscaling.autoscaling_group_name` | Auto Scaling Group name for operations and monitoring. |
| `launch_template_id` | `string` | `module.autoscaling.launch_template_id` | Launch template identifier created for the compute fleet. |
| `instance_security_group_id` | `string` | `module.instance_sg.security_group_id` | Security group ID attached to application instances. |

---

## 4. Security Controls

| Control | Enforcement | Module Config | Reference |
|---------|-------------|---------------|-----------|
| Encryption at rest | Preserve the `autoscaling` module's launch-template and EBS encryption defaults; no consumer input disables storage encryption, and the AMI-backed instances inherit encrypted volume behavior supported by the module. | `autoscaling`: do not set any encryption-disabling launch template or block-device overrides; preserve secure defaults from `research-security-cost.md`. | CIS AWS Foundations Benchmark v1.5 `2.2` (EBS encryption by default); AWS Well-Architected Security `SEC08-BP01` |
| Encryption in transit | Prefer an HTTPS ALB listener when `certificate_arn` is provided; otherwise the development deployment may run HTTP-only at the ALB edge without weakening any documented module secure default, and ALB-to-instance traffic remains constrained to the application port behind security groups. | `alb`: `listeners` configured for `HTTPS:443` when `certificate_arn != ""`, otherwise `HTTP:80`; no module TLS enforcement is disabled. | AWS Well-Architected Security `SEC09-BP01` |
| Public access | Make the ALB the only public endpoint and keep instances non-public by allowing inbound instance traffic only from the ALB security group. | `alb`: public listener ingress from `alb_ingress_cidrs`; `instance_sg`: `computed_ingress_with_source_security_group_id = module.alb.security_group_id`; `autoscaling`: instances receive only `module.instance_sg.security_group_id`. | AWS Well-Architected Security `SEC05-BP01`; CIS AWS Foundations Benchmark v1.5 `5.1` |
| IAM least privilege | Use HCP Terraform dynamic AWS credentials from the shared project variable set, avoid static keys, and rely on module-managed service integration rather than broad consumer-defined IAM policies. | `provider.aws`: authentication via `agent_AWS_Dynamic_Creds`; no `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`; `autoscaling`, `alb`, and `cloudwatch` receive only the specific identifiers they need. | AWS Well-Architected Security `SEC03-BP01`, `SEC03-BP02` |
| Logging | Enable alarm-based operational detection through the `cloudwatch` module for ASG CPU, ALB 5XX, and healthy-host metrics, while preserving AWS-managed service telemetry and not disabling any documented module monitoring defaults. | `cloudwatch`: alarm definitions for `AutoScalingGroupName`, `LoadBalancer`, and `TargetGroup` dimensions; `autoscaling` and `alb`: keep module monitoring defaults intact. | AWS Well-Architected Security `SEC04-BP02`; AWS Well-Architected Operational Excellence `OPS08-BP01` |
| Tagging | Enforce organization-standard tags at the provider level and pass tags through each module so all deployed resources inherit `ManagedBy`, `Environment`, `Project`, and `Owner`. | `provider.aws.default_tags`: `ManagedBy`, `Environment`, `Project`, `Owner`; `alb`, `instance_sg`, `autoscaling`, `cloudwatch`: pass shared `tags` input. | AWS Well-Architected Operational Excellence `OPS01-BP03` |

---

## 5. Implementation Checklist

- [ ] **A: Foundation files** -- Create `versions.tf`, `backend.tf`, and `providers.tf` with Terraform/HCP Terraform settings, provider constraints, remote workspace configuration, dynamic-credentials-compatible provider setup, and required `default_tags`.
- [ ] **B: Interface files** -- Create `variables.tf`, `outputs.tf`, and `terraform.auto.tfvars.example` with every deployment input and output defined exactly as specified, including validation rules and example non-secret values.
- [ ] **C: Discovery and naming files** -- Create `data.tf` and `locals.tf` for default VPC discovery, deterministic two-AZ subnet selection, shared naming conventions, common tags, and any simple type transformations needed by module inputs.
- [ ] **D: Composition file** -- Create `main.tf` with the `alb`, `instance_sg`, `autoscaling`, and `cloudwatch` module calls wired exactly to the documented inputs, including ALB listener/target-group settings, target tracking policy, and CloudWatch alarm definitions.
- [ ] **E: Documentation file** -- Create `README.md` with deployment purpose, prerequisites, required workspace settings, apply workflow, validation commands, and destroy guidance for the sandbox environment.

---

## 6. Open Questions

None.

---
