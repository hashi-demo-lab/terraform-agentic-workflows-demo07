locals {
  name_prefix = format("%s-%s", var.project_name, var.environment)

  api_name                   = format("%s-api", local.name_prefix)
  assets_bucket_name_prefix  = format("%s-assets", local.name_prefix)
  dynamodb_table_name        = format("%s-table", local.name_prefix)
  lambda_duration_alarm_name = format("%s-duration", local.lambda_function_name)
  lambda_error_alarm_name    = format("%s-errors", local.lambda_function_name)
  lambda_function_name       = format("%s-function", local.name_prefix)
  lambda_throttle_alarm_name = format("%s-throttles", local.lambda_function_name)
}
