locals {
  common_tags = {
    Application = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
    Project     = var.project
  }

  default_subnet_ids_by_az = {
    for subnet in data.aws_subnet.default :
    subnet.availability_zone => subnet.id
    if subnet.default_for_az && startswith(subnet.availability_zone, var.aws_region)
  }

  selected_default_subnet_azs = slice(
    sort(keys(local.default_subnet_ids_by_az)),
    0,
    min(length(local.default_subnet_ids_by_az), 2),
  )

  selected_default_subnet_ids = [
    for availability_zone in local.selected_default_subnet_azs :
    local.default_subnet_ids_by_az[availability_zone]
  ]

  name_prefix = "${var.service_name}-${var.environment}"

  alb_name                       = "${local.name_prefix}-alb"
  autoscaling_name               = "${local.name_prefix}-asg"
  autoscaling_image_architecture = startswith(var.instance_type, "t4g.") ? "arm64" : "x86_64"
  autoscaling_image_id = coalesce(
    var.image_id,
    try(nonsensitive(data.aws_ssm_parameter.amazon_linux[0].value), null),
  )
  amazon_linux_ami_parameter_name = format(
    "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-%s",
    local.autoscaling_image_architecture,
  )

  alb_ingress_cidrs = length(var.alb_ingress_cidrs) > 0 ? tolist(var.alb_ingress_cidrs) : [
    data.aws_vpc.default.cidr_block,
  ]
  alarm_notification_arns = tolist(var.alarm_notification_arns)
  certificate_discovery_enabled = (
    var.certificate_arn == null &&
    var.certificate_domain != null
  )
  listener_certificate_arn = (
    var.certificate_arn != null
    ? var.certificate_arn
    : try(data.aws_acm_certificate.selected[0].arn, null)
  )

  # [SECURITY OVERRIDE] This fallback is allowed only for sandbox E2E validation
  # when no ACM certificate override is provided and certificate discovery is not
  # configured. The ALB remains internal-only, ingress stays scoped to approved
  # VPC CIDRs, and instances still accept traffic only from the ALB security group.
  sandbox_http_listener_fallback_enabled = (
    var.project == "sandbox" &&
    local.listener_certificate_arn == null &&
    !local.certificate_discovery_enabled
  )

  alb_internal      = true
  listener_port     = local.sandbox_http_listener_fallback_enabled ? 80 : 443
  listener_protocol = local.sandbox_http_listener_fallback_enabled ? "HTTP" : "HTTPS"
  ssl_policy        = local.sandbox_http_listener_fallback_enabled ? null : "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
}
