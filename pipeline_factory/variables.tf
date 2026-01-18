variable "pipeline_name" {
  type        = string
  description = "Name of the pipeline"
}

variable "tasks_configuration" {
  type = map(object({
    type : string,
    path : string,
    infra_type : string,
    infra_config : map(string),
    input_tables : optional(list(string), []),
    output_tables : optional(map(object({
      ingestion_mode : optional(string),
      upsert_keys : optional(list(string), []),
      partition_keys : optional(list(string), [])
    })), {}),
    additional_parameters : optional(map(string), {}),
    additional_rebuild_trigger : optional(any, {}),
    additional_permissions : optional(string, null)
  }))
  description = "Maps of all the configurations of the tasks of the pipeline"
}

variable "trigger" {
  type = object({
    type       = string
    argument   = string
    parameters = optional(string, "{}")
  })
  description = "Configuration of the trigger of the pipeline"
  default = {
    "type" : "none",
    "argument" : "none"
  }
}

variable "failure_notification_receivers" {
  type        = list(string)
  description = "List of email addresses to which send an enamil if the pipeline fails"
  default     = []
}

variable "orchestration_configuration_template_file_path" {
  type        = string
  description = "Path of the template file for the orchestration configuration of the tasks of the pipeline"
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
    ecs_sandbox_image_uri            = string
    codeartifact_repository_endpoint = string
    failure_notification_receivers   = list(string)
  })
}

variable "database_description" {
  type        = string
  description = "Description of the database of the pipeline"
  default     = ""
}

variable "skip_pipeline_database_creation" {
  type        = bool
  description = "If true, pipeline_factory will not create the pipeline glue database. Useful if you plan to use only the domain glue database"
  default     = false
}
