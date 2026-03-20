provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        ManagedBy   = "terraform"
        Application = var.project_name
        Environment = var.environment
        Project     = var.project_name
        Owner       = var.owner
      },
      var.additional_tags
    )
  }

  # Dynamic credentials are supplied by the HCP Terraform
  # project variable set agent_AWS_Dynamic_Creds.
}
