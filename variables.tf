variable "additional_tags" {
  description = "Extra organization-specific tags merged with the required provider default tags."
  type        = map(string)
  default     = {}

  validation {
    condition = length(
      setintersection(
        toset(keys(var.additional_tags)),
        toset(["ManagedBy", "Environment", "Project", "Owner"])
      )
    ) == 0
    error_message = "additional_tags must not override ManagedBy, Environment, Project, or Owner."
  }
}

variable "alarm_actions" {
  description = "Optional alarm action ARNs, such as an SNS topic, attached to each CloudWatch alarm."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.alarm_actions : can(regex("^arn:[^:]+:[^:]*:[^:]*:[^:]*:.+$", arn))
    ])
    error_message = "Each alarm_actions value must be a valid AWS ARN."
  }
}

variable "aws_region" {
  description = "AWS region used by the sandbox consumer deployment."
  type        = string
  default     = "ap-southeast-2"

  validation {
    condition     = var.aws_region == "ap-southeast-2"
    error_message = "aws_region must be ap-southeast-2 for this design."
  }
}

variable "dynamodb_hash_key" {
  description = "Partition key name for the application DynamoDB table."
  type        = string
  default     = "id"

  validation {
    condition     = length(trimspace(var.dynamodb_hash_key)) > 0
    error_message = "dynamodb_hash_key must be non-empty."
  }
}

variable "environment" {
  description = "Environment tag and naming suffix for the sandbox deployment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, or prod."
  }
}

variable "lambda_architectures" {
  description = "Lambda CPU architecture list; arm64 is the default cost-optimized choice."
  type        = list(string)
  default     = ["arm64"]

  validation {
    condition = length(var.lambda_architectures) > 0 && alltrue([
      for architecture in var.lambda_architectures : contains(["arm64", "x86_64"], architecture)
    ])
    error_message = "lambda_architectures values must be arm64 or x86_64."
  }
}

variable "lambda_handler" {
  description = "Handler entry point for the Lambda function."
  type        = string
  default     = "app.handler"

  validation {
    condition     = can(regex("^[^.]+\\.[^.]+$", var.lambda_handler))
    error_message = "lambda_handler must be in file.function form."
  }
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention period for the Lambda log group."
  type        = number
  default     = 14

  validation {
    condition     = contains([7, 14, 30], var.lambda_log_retention_days)
    error_message = "lambda_log_retention_days must be one of 7, 14, or 30."
  }
}

variable "lambda_memory_mb" {
  description = "Memory size for the Lambda function."
  type        = number
  default     = 128

  validation {
    condition     = var.lambda_memory_mb >= 128 && var.lambda_memory_mb <= 10240
    error_message = "lambda_memory_mb must be between 128 and 10240."
  }
}

variable "lambda_runtime" {
  description = "Lambda runtime for the application function."
  type        = string
  default     = "python3.12"

  validation {
    condition = contains([
      "nodejs20.x",
      "nodejs22.x",
      "python3.11",
      "python3.12",
      "provided.al2",
      "provided.al2023",
    ], var.lambda_runtime)
    error_message = "lambda_runtime must be a runtime supported by the private Lambda module for this workload."
  }
}

variable "lambda_source_path" {
  description = "Filesystem path passed to the Lambda module for packaging or existing artifact reference."
  type        = string

  validation {
    condition     = length(trimspace(var.lambda_source_path)) > 0
    error_message = "lambda_source_path must be a non-empty relative or absolute path."
  }
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout used for the development workload."
  type        = number
  default     = 10

  validation {
    condition     = var.lambda_timeout_seconds >= 3 && var.lambda_timeout_seconds <= 30
    error_message = "lambda_timeout_seconds must be between 3 and 30."
  }
}

variable "owner" {
  description = "Owning team or person recorded in tags and operational metadata."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must be non-empty."
  }
}

variable "project_name" {
  description = "Canonical project label used for tags and generated resource names."
  type        = string
  default     = "consumer-serverless"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 characters of lowercase letters, numbers, or hyphens."
  }
}
