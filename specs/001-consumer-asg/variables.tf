variable "alarm_notification_arns" {
  description = "Optional SNS topics notified by CloudWatch alarm actions."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.alarm_notification_arns : startswith(arn, "arn:aws:sns:")
    ])
    error_message = "alarm_notification_arns must contain only SNS topic ARNs when provided."
  }
}

variable "alb_ingress_cidrs" {
  description = "Optional IPv4 CIDR ranges allowed to reach the internal ALB listener. When empty, the default VPC CIDR is allowed."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.alb_ingress_cidrs : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$", cidr)) && can(cidrhost(cidr, 0))
    ])
    error_message = "alb_ingress_cidrs must contain only valid IPv4 CIDR ranges."
  }
}

variable "aws_region" {
  description = "AWS region for all provider and module operations."
  type        = string
  default     = "ap-southeast-2"

  validation {
    condition     = var.aws_region == "ap-southeast-2"
    error_message = "aws_region must be ap-southeast-2 for this deployment."
  }
}

variable "certificate_arn" {
  description = "Optional ACM certificate ARN presented by the internal HTTPS ALB listener. When null, Terraform discovers a suitable issued certificate in the target region."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.certificate_arn == null ||
      (trimspace(var.certificate_arn) != "" && startswith(var.certificate_arn, "arn:aws:acm:"))
    )
    error_message = "certificate_arn must be null or start with arn:aws:acm:."
  }
}

variable "certificate_domain" {
  description = "Optional ACM certificate domain to narrow automatic certificate discovery when certificate_arn is not provided."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.certificate_domain == null ||
      trimspace(var.certificate_domain) != ""
    )
    error_message = "certificate_domain must be null or a non-empty domain name."
  }
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for target tracking scaling."
  type        = number
  default     = 60

  validation {
    condition     = var.cpu_target_value >= 10 && var.cpu_target_value <= 90
    error_message = "cpu_target_value must be between 10 and 90."
  }
}

variable "desired_capacity" {
  description = "Steady-state instance count for development traffic."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_capacity >= 1
    error_message = "desired_capacity must be at least 1."
  }
}

variable "environment" {
  description = "Environment tag and environment-specific naming discriminator."
  type        = string
  default     = "development"

  validation {
    condition     = var.environment == "development"
    error_message = "environment must be development."
  }
}

variable "health_check_grace_period" {
  description = "Warm-up period before ELB health checks affect replacement decisions."
  type        = number
  default     = 300

  validation {
    condition     = var.health_check_grace_period >= 0 && var.health_check_grace_period <= 900
    error_message = "health_check_grace_period must be between 0 and 900."
  }
}

variable "health_check_path" {
  description = "HTTP health-check path used by the load balancer target group."
  type        = string
  default     = "/health"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with /."
  }
}

variable "image_id" {
  description = "Optional AMI ID override used by the launch template for application instances. When null, Terraform discovers the latest regional Amazon Linux 2023 AMI that matches the selected instance architecture."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.image_id == null ||
      (trimspace(var.image_id) != "" && startswith(var.image_id, "ami-"))
    )
    error_message = "image_id must be null or start with ami-."
  }
}

variable "instance_port" {
  description = "Application port exposed by each instance and registered in the target group."
  type        = number
  default     = 80

  validation {
    condition     = var.instance_port >= 1 && var.instance_port <= 65535
    error_message = "instance_port must be between 1 and 65535."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the Auto Scaling Group."
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t3.micro", "t4g.micro"], var.instance_type)
    error_message = "instance_type must be one of the permitted development instance types: t3.micro or t4g.micro."
  }
}

variable "max_size" {
  description = "Maximum burst capacity permitted in the sandbox environment."
  type        = number
  default     = 2

  validation {
    condition     = var.max_size <= 2
    error_message = "max_size must be less than or equal to 2."
  }
}

variable "min_size" {
  description = "Minimum instance count for the Auto Scaling Group."
  type        = number
  default     = 1

  validation {
    condition     = var.min_size >= 1
    error_message = "min_size must be at least 1."
  }
}

variable "owner" {
  description = "Owner tag value for support and accountability."
  type        = string

  validation {
    condition     = trimspace(var.owner) != ""
    error_message = "owner must be non-empty."
  }
}

variable "project" {
  description = "Project tag value propagated through provider default tags."
  type        = string
  default     = "sandbox"

  validation {
    condition     = trimspace(var.project) != ""
    error_message = "project must be non-empty."
  }
}

variable "service_name" {
  description = "Canonical name prefix used for load balancer, Auto Scaling, and alarm naming."
  type        = string
  default     = "consumer-asg"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_name))
    error_message = "service_name must match ^[a-z0-9-]+$."
  }
}

check "capacity_relationships" {
  assert {
    condition     = var.min_size <= var.desired_capacity
    error_message = "min_size must be less than or equal to desired_capacity."
  }

  assert {
    condition     = var.desired_capacity <= var.max_size
    error_message = "desired_capacity must be less than or equal to max_size."
  }
}
