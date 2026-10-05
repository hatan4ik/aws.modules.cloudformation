variable "region" {
  description = "Region of the StackSet, and the one region its instance deploys to."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "StackSet name."
  type        = string
  default     = "self-managed-bootstrap"
}

variable "target_account_id" {
  description = "12-digit ID of the target account the StackSet deploys to."
  type        = string
}

variable "target_account_role_arn" {
  description = "ARN of a role in the target account that Terraform assumes to create the execution role there (for example OrganizationAccountAccessRole, or your landing zone's deployment role). It needs IAM permissions to create a role and its policies."
  type        = string
}
