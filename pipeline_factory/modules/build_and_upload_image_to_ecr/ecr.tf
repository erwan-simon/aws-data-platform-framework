resource "aws_ecr_repository" "main" {
  name = "${replace(var.environment_name, "_", "-")}-${var.resources_suffix}"

  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    "${var.domain_object.project_name}:jupyter_sandbox" = "allowed"
  }
}

resource "aws_ecr_lifecycle_policy" "main" {
  repository = aws_ecr_repository.main.name

  policy = <<eof
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Rule 1",
            "selection": {
                "tagStatus": "any",
                "countType": "imageCountMoreThan",
                "countNumber": 1
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
eof
}
