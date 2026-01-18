data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = toset(["${var.project_name}_network_platform_prod"])
  }
}

data "aws_subnets" "main" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = {
    Tier = var.use_public_subnets ? "Public" : "Private"
  }
}

data "aws_codeartifact_repository_endpoint" "main" {
  domain     = aws_codeartifact_repository.main.domain
  repository = aws_codeartifact_repository.main.repository
  format     = "pypi"
}

data "aws_codeartifact_authorization_token" "main" {
  domain = aws_codeartifact_repository.main.domain
}
