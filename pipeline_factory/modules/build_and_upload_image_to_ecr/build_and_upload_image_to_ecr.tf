locals {
  total_rebuild_trigger = merge(var.rebuild_trigger, {
    # compute a map composed of the relative file path as key and the file hash as value, for every files of your processing jobs, recursively. Ignoring some irrelevant path patterns
    task_code_hashes = jsonencode({
      for file_path in fileset(trimsuffix(var.source_code_path, "/"), "**") :
      file_path => filemd5("${path.root}/${trimsuffix(var.source_code_path, "/")}/${file_path}")
      if alltrue([
        for directory_pattern_to_ignore in [
          ".mypy_cache/", ".ipynb_checkpoints/", "__pycache__/"
        ] :
        !strcontains(file_path, directory_pattern_to_ignore)
      ]) # ignoring path if it contains any of the irrelevant directory
    })
    requirements_file_hash = fileexists("${var.source_code_path}/requirements.txt") ? filemd5("${var.source_code_path}/requirements.txt") : "absent"
    dockerfile_hash        = filemd5("${var.dockerfile_path}/Dockerfile"),
    base_image_uri         = var.base_image_uri,
  })
  # AWS lambda does not detect image change if tag is the same ('latest' for exemple).
  # The `runtime-` prefix lets the ECR lifecycle policy target runtime images specifically
  # without sweeping the `:buildcache` tag — see ecr.tf for the matching rule.
  image_tag           = "runtime-${sha1(jsonencode(local.total_rebuild_trigger))}"
  cleaned_source_path = trimsuffix(var.source_code_path, "/")
}

# Ground the build trigger in ECR's actual state, not just terraform inputs.
# When `image_tag` is non-monotonic across applies (different branches push
# different sha1 values into the same repo) the lifecycle policy can expire
# a manifest terraform later expects — the EMR Serverless update then 404s.
# Reading ECR at plan-time and feeding the result into `triggers_replace`
# turns "image was expired" into a normal rebuild trigger, making the system
# self-healing.
#
# The external provider is used (not `data "aws_ecr_image"`) because the AWS
# provider's data sources raise a plan error on `ImageNotFoundException`,
# which is precisely the case we want to handle as data. The wrapper script
# swallows that exit code and returns `{"present_tag": "MISSING"}`.
data "external" "ecr_image_presence" {
  program = ["bash", "${path.module}/check_ecr_image_presence.sh"]
  query = {
    repository_name = aws_ecr_repository.main.name
    image_tag       = local.image_tag
    region          = var.domain_object.aws_region
    role_to_assume  = var.role_to_assume_arn
  }
}

resource "terraform_data" "image_build_and_upload" {
  provisioner "local-exec" {
    command = join(" ", [
      "/bin/bash",
      "build_and_upload_image_to_ecr.sh",
      var.base_image_uri,
      var.domain_object.project_name,
      var.domain_object.domain_name,
      var.domain_object.stage_name,
      var.pipeline_name,
      var.task_name,
      "'${jsonencode(var.task_configuration["input_tables"])}'",
      "'${jsonencode(var.task_configuration["output_tables"])}'",
      tostring(fileexists("${var.task_configuration["path"]}/code/main.sql")), # IS_SQL_JOB
      var.dockerfile_path,
      "${abspath(path.root)}/${local.cleaned_source_path}",
      local.cleaned_source_path,
      var.domain_object.aws_caller_identity_account_id,
      var.domain_object.aws_region,
      aws_ecr_repository.main.name,
      local.image_tag,
      "${replace(var.domain_object.codeartifact_repository_endpoint, "https://", "")}simple", # URL of CodeArtifact repository endpoint formatted to please pip
      var.package_datalake_sdk,
      var.role_to_assume_arn
    ])
    working_dir = path.module
  }
  # `image_tag` is included so a change to the tag scheme itself (e.g. the `runtime-` prefix
  # above) forces a rebuild — `total_rebuild_trigger` alone doesn't see derivation tweaks.
  # `ecr_presence` flips to "MISSING" when the expected manifest isn't in ECR, which
  # forces a rebuild even if inputs are unchanged (self-healing after lifecycle expiry).
  triggers_replace = merge(local.total_rebuild_trigger, {
    image_tag    = local.image_tag
    ecr_presence = data.external.ecr_image_presence.result.present_tag
  })
  depends_on = [aws_ecr_repository.main]
}

