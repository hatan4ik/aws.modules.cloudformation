output "stack_arn" {
  description = "ARN of the stack."
  value       = module.vendor_agent.arn
}

output "log_group_arn" {
  description = "ARN of the log group the template created, read from the stack's Outputs."
  value       = module.vendor_agent.outputs["LogGroupArn"]
}
