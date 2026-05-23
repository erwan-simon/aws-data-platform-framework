output "image_uri" {
  value      = "${aws_ecr_repository.main.repository_url}:${local.image_tag}"
  depends_on = [terraform_data.image_build_and_upload]
}

output "ecr_arn" {
  value = aws_ecr_repository.main.arn
}

output "ecr_name" {
  value = aws_ecr_repository.main.name
}

output "rebuild_trigger" {
  value = local.total_rebuild_trigger
}
