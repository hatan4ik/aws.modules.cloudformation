variable "region" {
  description = "Region of the StackSet itself, and the one region its instances deploy to."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "StackSet name."
  type        = string
  default     = "security-audit-role-baseline"
}

variable "security_account_id" {
  description = "12-digit ID of the security tooling account the audit role trusts."
  type        = string
}

variable "organizational_unit_ids" {
  description = "IDs of the OUs (ou-xxxx-yyyyyyyy), or the organization root ID (r-xxxx), whose accounts get the role."
  type        = set(string)
}

variable "call_as" {
  description = "SELF when running in the organization's management account, DELEGATED_ADMIN when running in a registered StackSets delegated administrator account."
  type        = string
  default     = "DELEGATED_ADMIN"
}
