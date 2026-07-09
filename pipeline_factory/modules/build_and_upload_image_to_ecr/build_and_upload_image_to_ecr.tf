locals {
  # Empty string when the caller left the var null: keeps the build-arg passing
  # inert on Dockerfiles that don't declare the ARG, and preserves position ${20}
  # of the shell command below when the caller opts out.
  install_agent_extras_arg = var.install_datalake_sdk_agent_extras == null ? "" : tostring(var.install_datalake_sdk_agent_extras)

  total_rebuild_trigger = merge(var.rebuild_trigger,
    {
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
    },
    # `install_datalake_sdk_agent_extras` only enters the trigger when the
    # caller sets it explicitly. Consumers that don't declare the matching
    # ARG in their Dockerfile leave the variable null → key absent → their
    # `image_tag` isn't invalidated when the value flips on another caller.
    var.install_datalake_sdk_agent_extras == null ? {} : {
      install_datalake_sdk_agent_extras = tostring(var.install_datalake_sdk_agent_extras)
    },
  )
  # AWS lambda does not detect image change if tag is the same ('latest' for exemple).
  # The `runtime-` prefix lets the ECR lifecycle policy target runtime images specifically
  # without sweeping the `:buildcache` tag — see ecr.tf for the matching rule.
  image_tag           = "runtime-${sha1(jsonencode(local.total_rebuild_trigger))}"
  cleaned_source_path = trimsuffix(var.source_code_path, "/")
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
      # role_to_assume_arn is empty for the failsafe_shutdown Lambda build (Lambda has its own
      # exec role, no cross-account assume needed). Shell-quote it so a `join`-emitted empty
      # token stays a proper positional arg at ${19} — otherwise it collapses under adjacent
      # spaces and every subsequent ${N} shifts down by one (bug seen in v6.3 CI: the
      # INSTALL_DATALAKE_SDK_AGENT_EXTRAS build-arg silently landed as an empty string).
      "\"${var.role_to_assume_arn}\"",
      "\"${local.install_agent_extras_arg}\""
    ])
    working_dir = path.module
  }
  # `image_tag` is included so a change to the tag scheme itself (e.g. the `runtime-` prefix
  # above) forces a rebuild — `total_rebuild_trigger` alone doesn't see derivation tweaks.
  # The guarantee "resource success ⇒ image readable in ECR" is held by the script's
  # post-push wait-loop (script exit 0 only after `aws ecr describe-images` confirms the
  # tag is visible), not by a plan-time data source — a presence data source fed into
  # `triggers_replace` flips between the plan-of-push apply (image absent → MISSING) and
  # the next apply (image present → tag), forcing a spurious rebuild on every cycle.
  triggers_replace = merge(local.total_rebuild_trigger, {
    image_tag = local.image_tag
  })
  depends_on = [aws_ecr_repository.main]
}

