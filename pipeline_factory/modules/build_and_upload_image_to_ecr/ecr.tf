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

  # Rule 1 keeps the `:buildcache` tag indefinitely (BuildKit's mode=max cache
  # manifest, written and pulled by build_and_upload_image_to_ecr.sh). Rule 2
  # keeps only the most recent runtime image — scoped via the `runtime-` tag
  # prefix (set in build_and_upload_image_to_ecr.tf) so the buildcache image,
  # which lives in the same repo, is never swept by this rule.
  policy = <<eof
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep the BuildKit cache manifest (only one ever has this tag)",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["buildcache"],
                "countType": "imageCountMoreThan",
                "countNumber": 1
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 2,
            "description": "Keep only the latest runtime image (scoped by runtime- prefix to spare buildcache)",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["runtime-"],
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
