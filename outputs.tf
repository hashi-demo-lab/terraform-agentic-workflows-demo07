output "api_invoke_url" {
  description = "Invoke URL for the development HTTP API."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "assets_bucket_name" {
  description = "Name of the private S3 bucket storing application assets."
  value       = module.assets_bucket.s3_bucket_name
}

output "default_vpc_id" {
  description = "Identifier of the discovered existing default VPC in the target account."
  value       = data.aws_vpc.default.id
}

output "dynamodb_table_name" {
  description = "Name of the application DynamoDB table."
  value       = module.app_table.dynamodb_table_id
}

output "lambda_function_arn" {
  description = "ARN of the deployed Lambda function."
  value       = module.lambda_function.lambda_function_arn
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function."
  value       = module.lambda_function.lambda_function_name
}

output "lambda_log_group_name" {
  description = "CloudWatch Logs group name for the Lambda function."
  value       = module.lambda_function.lambda_cloudwatch_log_group_name
}
