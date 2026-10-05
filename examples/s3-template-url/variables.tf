variable "region" {
  description = "AWS region the stack is created in."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Stack name."
  type        = string
  default     = "marketplace-solution-example"
}

variable "template_url" {
  description = "https:// URL of the vendor's template object in Amazon S3, ideally a versioned key."
  type        = string
}

variable "parameters" {
  description = "Template parameters the vendor documents, as strings."
  type        = map(string)
  default     = {}
}

variable "cloudformation_role_arn" {
  description = "ARN of an existing IAM role that trusts cloudformation.amazonaws.com and holds exactly the permissions the vendor template needs."
  type        = string
}

variable "notification_topic_arn" {
  description = "Optional ARN of an existing SNS topic that receives the stack's events. null sends none."
  type        = string
  default     = null
}
