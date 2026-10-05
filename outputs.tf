output "id" {
  description = "Stack ID. CloudFormation stack IDs are the stack ARN, so this equals arn; it is kept under the fleet's usual name."
  value       = aws_cloudformation_stack.this.id
}

output "arn" {
  description = "Stack ARN (arn:<partition>:cloudformation:<region>:<account>:stack/<name>/<uuid>), read from the stack ID rather than constructed, because the trailing UUID is assigned by CloudFormation."
  value       = aws_cloudformation_stack.this.id
}

output "name" {
  description = "Stack name."
  value       = aws_cloudformation_stack.this.name
}

output "outputs" {
  description = "The stack's own CloudFormation Outputs as a map of output key to value. This is the composition point for anything downstream of the stack."
  value       = aws_cloudformation_stack.this.outputs
}
