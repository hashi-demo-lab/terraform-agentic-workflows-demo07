terraform {
  required_version = ">= 1.5.7"

  cloud {
    organization = "__TFE_ORG__"

    workspaces {
      name = "__TFE_WORKSPACE__"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.5"
    }
  }
}
