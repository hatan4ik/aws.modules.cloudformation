variable "region" {
  description = "AWS region the stack is created in."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Stack name; also passed to the template as AgentName."
  type        = string
  default     = "vendor-agent-example"
}

variable "cloudformation_role_arn" {
  description = "ARN of an existing IAM role that trusts cloudformation.amazonaws.com and may manage CloudWatch Logs log groups. CloudFormation assumes it for every operation on the stack."
  type        = string
}

variable "notification_topic_arn" {
  description = "ARN of an existing SNS topic that receives the stack's events."
  type        = string
}

variable "destination_arn" {
  description = "Optional ARN of an existing log destination (Kinesis stream, Firehose, or Lambda) to forward the agent's logs to. null skips the subscription."
  type        = string
  default     = null
}
