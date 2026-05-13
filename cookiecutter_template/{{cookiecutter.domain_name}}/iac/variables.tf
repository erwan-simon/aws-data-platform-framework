variable "project_name" {
  type        = string
  description = "Name of the project"
}

variable "git_repository" {
  type        = string
  description = "git respository from which this resource is from"
  default     = "none"
}

variable "role_to_assume_arn" {
  type        = string
  description = "ARN of the role to assume to deploy the resources"
  default     = ""
}

variable "failure_notification_receivers" {
  type        = string
  description = "List of email adresses separated by comma to send pipeline failure notifications to"
  default     = ""
}


variable "datalake_admin_principal_arns" {
  type        = string
  description = "List of IAM principal ARNS separated by comma that have to be lakeformation admins of the created databases"
  default     = ""
}
