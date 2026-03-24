data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "default" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

data "aws_acm_certificate" "selected" {
  count = var.certificate_arn == null && var.certificate_domain != null ? 1 : 0

  domain      = var.certificate_domain
  tags        = var.certificate_domain == null ? {} : null
  most_recent = true
  region      = var.aws_region
  statuses    = ["ISSUED"]
  types       = ["AMAZON_ISSUED", "IMPORTED"]
}

data "aws_ssm_parameter" "amazon_linux" {
  count = var.image_id == null ? 1 : 0

  name = local.amazon_linux_ami_parameter_name
}

check "default_vpc_subnet_selection" {
  assert {
    condition     = length(local.selected_default_subnet_ids) == 2
    error_message = "The default VPC must include at least two default subnets in distinct ${var.aws_region} Availability Zones."
  }
}

check "listener_certificate_selection" {
  assert {
    condition     = local.listener_certificate_arn != null || local.sandbox_http_listener_fallback_enabled
    error_message = "Set certificate_arn or set certificate_domain so Terraform can discover an issued ACM certificate in ${var.aws_region}. The internal HTTP listener fallback is permitted only for sandbox runs."
  }
}

check "autoscaling_image_selection" {
  assert {
    condition     = local.autoscaling_image_id != null
    error_message = "Set image_id or allow Terraform to discover the latest Amazon Linux 2023 AMI for the selected instance architecture in ${var.aws_region}."
  }
}
