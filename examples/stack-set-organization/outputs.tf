output "stack_set_arn" {
  description = "ARN of the StackSet."
  value       = module.audit_role_baseline.arn
}

output "stack_instances" {
  description = "Per OU and region: the accounts the deployment reached and the stack each one runs."
  value       = module.audit_role_baseline.stack_instances
}
