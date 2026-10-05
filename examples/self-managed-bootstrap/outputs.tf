output "administration_role_arn" {
  description = "ARN of the StackSets administration role in the administrator account."
  value       = module.stack_set_administration_role.role_arn
}

output "execution_role_arn" {
  description = "ARN of the StackSets execution role in the target account."
  value       = module.stack_set_execution_role.role_arn
}

output "stack_set_arn" {
  description = "ARN of the StackSet."
  value       = module.parameter_baseline.arn
}

output "stack_instances" {
  description = "The instance in the target account and region, with its stack ID."
  value       = module.parameter_baseline.stack_instances
}
