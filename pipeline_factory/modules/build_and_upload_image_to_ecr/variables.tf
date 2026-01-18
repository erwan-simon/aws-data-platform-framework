variable "environment_name" {
  type        = string
  description = "Name of the environment which will be used as resources name prefix"
}

variable "resources_suffix" {
  type        = string
  description = "Suffix to use as created resources name"
}

variable "dockerfile_path" {
  type        = string
  description = "Path of the Dockerfile path"
}

variable "role_to_assume_arn" {
  type        = string
  description = "ARN of the IAM role to assume to perform AWS operation"
}

variable "source_code_path" {
  type        = string
  description = "Path of the source code to include in the job"
}

variable "rebuild_trigger" {
  type        = map(string)
  description = "Elements which if changed will trigger the rebuild of the Docker image"
  default     = {}
}

variable "domain_object" {
  description = "Domain object"
}

variable "pipeline_name" {
  type        = string
  description = "Name of the pipeline"
}

variable "task_name" {
  type        = string
  description = "Name of the task"
}

variable "task_configuration" {
  description = "Object containing the configuration of the task"
}

variable "base_image_uri" {
  type        = string
  description = "URI of a Docker image to use as a base image in the Dockerfile"
  default     = "None"
}

variable "package_datalake_sdk" {
  type        = bool
  description = "Should the build script package the datalake sdk or not"
  default     = false
}
