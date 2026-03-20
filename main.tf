resource "random_string" "bucket_suffix" {
  length  = 8
  lower   = true
  numeric = true
  special = false
  upper   = false
}

module "app_table" {
  source  = "app.terraform.io/hashi-demos-apj/dynamodb-table/aws"
  version = "~> 5.2"

  name     = local.dynamodb_table_name
  hash_key = var.dynamodb_hash_key

  attributes = [
    {
      name = var.dynamodb_hash_key
      type = "S"
    }
  ]

  billing_mode                   = "PAY_PER_REQUEST"
  server_side_encryption_enabled = true
}

module "assets_bucket" {
  source  = "app.terraform.io/hashi-demos-apj/s3-bucket/aws"
  version = "~> 6.0"

  environment = var.environment
  bucket      = format("%s-%s-assets-%s", var.project_name, var.environment, random_string.bucket_suffix.result)

  versioning = {
    enabled = true
  }

  block_public_acls        = true
  block_public_policy      = true
  control_object_ownership = true
  ignore_public_acls       = true
  object_ownership         = "BucketOwnerEnforced"
  restrict_public_buckets  = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = local.api_name
  protocol_type = "HTTP"

  description = "Development HTTP API for ${local.lambda_function_name}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.http_api.id
  name   = "$default"

  auto_deploy = true
  description = "Default development stage"
}

module "lambda_function" {
  source  = "app.terraform.io/hashi-demos-apj/lambda/aws"
  version = "~> 8.1"

  function_name = local.lambda_function_name
  source_path   = var.lambda_source_path
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime

  architectures                     = var.lambda_architectures
  memory_size                       = var.lambda_memory_mb
  timeout                           = var.lambda_timeout_seconds
  cloudwatch_logs_retention_in_days = var.lambda_log_retention_days

  attach_cloudwatch_logs_policy           = true
  attach_policy_statements                = true
  create_current_version_allowed_triggers = false
  create_role                             = true

  environment_variables = {
    ASSETS_BUCKET = module.assets_bucket.s3_bucket_name
    TABLE_NAME    = module.app_table.dynamodb_table_id
  }

  policy_statements = {
    dynamodb = {
      effect = "Allow"
      actions = [
        "dynamodb:DeleteItem",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:UpdateItem",
      ]
      resources = [
        module.app_table.dynamodb_table_arn,
        "${module.app_table.dynamodb_table_arn}/index/*",
      ]
    }
    s3 = {
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:PutObject",
      ]
      resources = [
        module.assets_bucket.s3_bucket_arn,
        "${module.assets_bucket.s3_bucket_arn}/*",
      ]
    }
  }

  allowed_triggers = {
    APIGateway = {
      service    = "apigateway"
      source_arn = "${aws_apigatewayv2_stage.default.execution_arn}/*"
    }
  }
}

# [CONSTITUTION DEVIATION] The private registry does not currently provide an
# API Gateway module, so the HTTP API is implemented as provider-native glue.
resource "aws_apigatewayv2_integration" "http_api" {
  api_id = aws_apigatewayv2_api.http_api.id

  description            = "Lambda proxy integration"
  integration_method     = "POST"
  integration_type       = "AWS_PROXY"
  integration_uri        = module.lambda_function.lambda_function_invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "$default"

  target = "integrations/${aws_apigatewayv2_integration.http_api.id}"
}
