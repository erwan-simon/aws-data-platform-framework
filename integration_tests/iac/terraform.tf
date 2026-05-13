provider "aws" {
  default_tags {
    tags = {
      Appli          = var.project_name
      Component      = local.domain_name
      Env            = terraform.workspace
      git_repository = var.git_repository
    }
  }
  assume_role {
    role_arn = var.role_to_assume_arn
  }
}

terraform {
  backend "s3" {
    key                  = "datalake_test.tfstate"
    workspace_key_prefix = ""
    encrypt              = true
    region               = "eu-west-1"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60.0, < 6.14.0"
    }
  }
}
