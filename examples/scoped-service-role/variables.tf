variable "region" {
  description = "Region the stack and its resources are created in."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Stack name. It also prefixes the bucket name and the SSM parameter path, which is how the service role's statements are scoped to this stack's resources; keep it at most 40 characters so the bucket name fits S3's 63."
  type        = string
  default     = "scoped-service-role"
}

variable "notification_topic_arn" {
  description = "ARN of an existing SNS topic that receives the stack's events."
  type        = string
}
