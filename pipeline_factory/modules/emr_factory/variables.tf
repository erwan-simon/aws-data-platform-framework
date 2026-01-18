variable "pipeline_name" {
  type        = string
  description = "Name of the pipeline"
}

variable "task_name" {
  type        = string
  description = "Name of the task"
}

variable "task_configuration" {
  type = object({
    type : string,
    path : string,
    infra_type : string
    infra_config : object({
      maximum_capacity_cpu : optional(string, "60 vCPU"),
      maximum_capacity_memory : optional(string, "120 GB"),
      maximum_capacity_disk : optional(string, "800 GB"),
      job_timeout_minutes : optional(number, 60),
      spark_executor_cores : optional(number, 4),
      spark_executor_memory : optional(string, "8g"),
      spark_executor_instances : optional(number, 4),
      spark_driver_cores : optional(number, 4),
      spark_driver_memory : optional(string, "8g")
    }),
    input_tables : optional(list(string), []),
    output_tables : optional(map(object({
      ingestion_mode : optional(string),
      upsert_keys : optional(list(string), []),
      partition_keys : optional(list(string), [])
    })), {}),
    additional_parameters : optional(map(string), {}),
    additional_rebuild_trigger : optional(any, {}),
    additional_permissions : optional(string, null)
  })
  description = "Configuration of the task"
}

variable "role_to_assume_arn" {
  type        = string
  description = "ARN of the role to assume to deploy the resources"
  default     = ""
}

variable "domain_object" {
  description = "Domain in which deploy the pipeline"
  type = object({
    project_name                     = string
    domain_name                      = string
    git_repository                   = string
    role_to_assume_arn               = string
    stage_name                       = string
    datalake_sdk_version             = string
    datalake_bucket_name             = string
    technical_bucket_name            = string
    tasks_security_group_id          = string
    failsafe_shutdown_lambda_arn     = string
    lakeformation_data_location_arn  = string
    domain_glue_database_name        = string
    datalake_admin_principal_arns    = list(string)
    use_public_subnets               = bool
    vpc_id                           = string
    subnets_list                     = list(string)
    aws_caller_identity_account_id   = string
    aws_region                       = string
    emr_sandbox_image_uri            = string
    codeartifact_repository_endpoint = string
  })
}

variable "pipeline_database_name" {
  type        = string
  description = "Name of the glue database created for this pipeline"
}

variable "dockerfile_path" {
  type        = string
  description = "Path of the Dockerfile to use"
}

variable "package_datalake_sdk" {
  type        = bool
  description = "Should the build script package the datalake sdk or not"
  default     = false
}
