output "stack_id" {
  description = "ID (ARN) of the stack."
  value       = module.marketplace_solution.id
}

output "stack_outputs" {
  description = "Everything the vendor template exports through its Outputs section."
  value       = module.marketplace_solution.outputs
}
