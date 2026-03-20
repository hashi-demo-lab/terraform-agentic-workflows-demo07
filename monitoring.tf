module "lambda_duration_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  alarm_name          = local.lambda_duration_alarm_name
  alarm_actions       = var.alarm_actions
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
    FunctionName = module.lambda_function.lambda_function_name
  }
  evaluation_periods = 1
  metric_name        = "Duration"
  namespace          = "AWS/Lambda"
  period             = 60
  statistic          = "Maximum"
  threshold          = floor(var.lambda_timeout_seconds * 1000 * 0.8)
  treat_missing_data = "notBreaching"
}

module "lambda_error_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  alarm_name          = local.lambda_error_alarm_name
  alarm_actions       = var.alarm_actions
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
    FunctionName = module.lambda_function.lambda_function_name
  }
  evaluation_periods = 1
  metric_name        = "Errors"
  namespace          = "AWS/Lambda"
  period             = 60
  statistic          = "Sum"
  threshold          = 0
  treat_missing_data = "notBreaching"
}

module "lambda_throttle_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  alarm_name          = local.lambda_throttle_alarm_name
  alarm_actions       = var.alarm_actions
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
    FunctionName = module.lambda_function.lambda_function_name
  }
  evaluation_periods = 1
  metric_name        = "Throttles"
  namespace          = "AWS/Lambda"
  period             = 60
  statistic          = "Sum"
  threshold          = 0
  treat_missing_data = "notBreaching"
}
