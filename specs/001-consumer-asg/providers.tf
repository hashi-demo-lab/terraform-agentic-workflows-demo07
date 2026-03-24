provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Application = var.service_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      Project     = var.project
    }
  }

  # Authentication is supplied by HCP Terraform dynamic AWS credentials
  # from the project-level agent_AWS_Dynamic_Creds variable set.
}
