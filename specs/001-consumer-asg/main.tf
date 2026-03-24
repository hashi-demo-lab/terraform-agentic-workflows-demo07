module "alb" {
  source  = "app.terraform.io/hashi-demos-apj/alb/aws"
  version = "~> 10.1"

  internal = local.alb_internal
  name     = local.alb_name
  vpc_id   = data.aws_vpc.default.id
  subnets  = local.selected_default_subnet_ids

  security_group_ingress_rules = {
    for index, cidr in local.alb_ingress_cidrs : "listener_${index}" => {
      cidr_ipv4   = cidr
      description = "Allow approved client access to the internal ALB listener"
      from_port   = local.listener_port
      ip_protocol = "tcp"
      to_port     = local.listener_port
    }
  }

  listeners = {
    app = merge(
      {
        port     = local.listener_port
        protocol = local.listener_protocol

        forward = {
          target_group_key = "app"
        }
      },
      local.listener_protocol == "HTTPS" ? {
        certificate_arn = local.listener_certificate_arn
        ssl_policy      = local.ssl_policy
        } : {
        # [SECURITY OVERRIDE] Sandbox-only E2E runs may use an internal HTTP
        # listener when no ACM certificate override or discovery input is
        # available. This keeps the ALB private while unblocking non-interactive
        # validation in the sandbox workspace.
      },
    )
  }

  target_groups = {
    app = {
      create_attachment = false
      name_prefix       = "app"
      port              = var.instance_port
      protocol          = "HTTP"
      target_type       = "instance"

      health_check = {
        enabled             = true
        healthy_threshold   = 3
        interval            = 30
        matcher             = "200-399"
        path                = var.health_check_path
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 6
        unhealthy_threshold = 3
      }
    }
  }

  tags = local.common_tags
}

module "instance_sg" {
  source  = "app.terraform.io/hashi-demos-apj/security-group/aws"
  version = "~> 5.3"

  computed_ingress_with_source_security_group_id = [
    {
      from_port                = var.instance_port
      protocol                 = "tcp"
      source_security_group_id = module.alb.security_group_id
      to_port                  = var.instance_port
    }
  ]
  description                                              = "Application instance security group for ${local.name_prefix}"
  egress_cidr_blocks                                       = []
  egress_ipv6_cidr_blocks                                  = []
  egress_rules                                             = []
  name                                                     = "${local.name_prefix}-instance"
  number_of_computed_ingress_with_source_security_group_id = 1
  vpc_id                                                   = data.aws_vpc.default.id

  tags = local.common_tags
}

module "autoscaling" {
  source  = "app.terraform.io/hashi-demos-apj/autoscaling/aws"
  version = "~> 9.0"

  desired_capacity          = var.desired_capacity
  health_check_grace_period = var.health_check_grace_period
  health_check_type         = "ELB"
  image_id                  = local.autoscaling_image_id
  instance_type             = var.instance_type
  max_size                  = var.max_size
  min_size                  = var.min_size
  name                      = local.autoscaling_name
  security_groups           = [module.instance_sg.security_group_id]
  vpc_zone_identifier       = local.selected_default_subnet_ids

  scaling_policies = {
    cpu_target_tracking = {
      policy_type = "TargetTrackingScaling"

      target_tracking_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
        target_value = var.cpu_target_value
      }
    }
  }

  traffic_source_attachments = {
    app = {
      traffic_source_identifier = module.alb.target_groups["app"].arn
      traffic_source_type       = "elbv2"
    }
  }

  tags = local.common_tags
}

module "cloudwatch" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//wrappers/metric-alarm"
  version = "~> 5.7"

  defaults = {
    alarm_actions = local.alarm_notification_arns
    ok_actions    = local.alarm_notification_arns
    tags          = local.common_tags
  }

  items = {
    alb_5xx = {
      alarm_description   = "Trigger when the ALB serves 5XX responses."
      alarm_name          = "${local.name_prefix}-alb-5xx"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      dimensions = {
        LoadBalancer = module.alb.arn_suffix
      }
      evaluation_periods = 1
      metric_name        = "HTTPCode_ELB_5XX_Count"
      namespace          = "AWS/ApplicationELB"
      period             = "60"
      statistic          = "Sum"
      threshold          = 1
      treat_missing_data = "notBreaching"
    }

    asg_cpu = {
      alarm_description   = "Trigger when average ASG CPU utilization exceeds the target tracking set point."
      alarm_name          = "${local.name_prefix}-asg-cpu-high"
      comparison_operator = "GreaterThanThreshold"
      dimensions = {
        AutoScalingGroupName = module.autoscaling.autoscaling_group_name
      }
      evaluation_periods = 2
      metric_name        = "CPUUtilization"
      namespace          = "AWS/EC2"
      period             = "120"
      statistic          = "Average"
      threshold          = var.cpu_target_value
      treat_missing_data = "notBreaching"
    }

    healthy_hosts = {
      alarm_description   = "Trigger when the target group has fewer than one healthy instance."
      alarm_name          = "${local.name_prefix}-healthy-hosts"
      comparison_operator = "LessThanThreshold"
      dimensions = {
        LoadBalancer = module.alb.arn_suffix
        TargetGroup  = module.alb.target_groups["app"].arn_suffix
      }
      evaluation_periods = 2
      metric_name        = "HealthyHostCount"
      namespace          = "AWS/ApplicationELB"
      period             = "60"
      statistic          = "Minimum"
      threshold          = 1
      treat_missing_data = "breaching"
    }
  }
}
