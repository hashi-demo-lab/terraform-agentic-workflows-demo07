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
  listener_certificate_arn = coalesce(
    var.certificate_arn,
    try(data.aws_acm_certificate.selected[0].arn, null),
  )

  alb_internal      = true
  listener_port     = 443
  listener_protocol = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
}
