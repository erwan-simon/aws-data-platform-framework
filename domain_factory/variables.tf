variable "project_name" {
  type        = string
  description = "Name of the project"
}

variable "domain_name" {
  type        = string
  description = "Name of the domain"
}

variable "stage_name" {
  type        = string
  description = "Name of the stage (dev, uat, prod,...)"
}

variable "git_repository" {
  type        = string
  description = "git respository from which this resource is from"
}

variable "role_to_assume_arn" {
  type        = string
  description = "ARN of the role to assume to deploy the resources"
  default     = ""
}

variable "datalake_admin_principal_arns" {
  type        = list(string)
  description = "List of the principal arns which will have admin access permissions to every databases and tables created by this domain"
  default     = []
}

variable "use_public_subnets" {
  type        = bool
  description = "Should the processing resources be put in Public or in Private subnets ? If Private, a NAT Gateway should exist to provide internet access"
  default     = true
}

variable "database_description" {
  type        = string
  description = "Description of the database of the domain"
  default     = ""
}

variable "skip_emr_serverless_sandbox_creation" {
  type        = bool
  description = "Skip the EMR Serverless Sandbox creation. The Docker image for it is very long to create, and useless if you do not plan to have a big volume of data."
  default     = true
}

variable "failure_notification_receivers" {
  type        = list(string)
  description = "List of emails to which to send failure notifications"
}

variable "enable_llm" {
  type        = bool
  description = "Enable the LLM features of the framework: create Bedrock inference profiles for the domain and let the failsafe shutdown Lambda call datalfred to diagnose pipeline failures. When false, no inference profiles are created and pipeline failure Slack messages skip the LLM analysis."
  default     = true
}
