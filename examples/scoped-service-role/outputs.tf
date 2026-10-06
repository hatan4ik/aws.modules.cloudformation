output "role_arn" {
  description = "ARN of the scoped CloudFormation service role."
  value       = module.cloudformation_role.role_arn
}

output "stack_id" {
  description = "ID (ARN) of the stack."
  value       = module.artifacts.id
}

output "bucket_name" {
  description = "Name of the bucket the stack created, from its BucketName output."
  value       = module.artifacts.outputs["BucketName"]
}
