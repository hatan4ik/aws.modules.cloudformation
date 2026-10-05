output "id" {
  description = "StackSet ID (<name>:<uuid>), as CloudFormation assigns it."
  value       = aws_cloudformation_stack_set.this.stack_set_id
}

output "arn" {
  description = "StackSet ARN."
  value       = aws_cloudformation_stack_set.this.arn
}

output "name" {
  description = "StackSet name."
  value       = aws_cloudformation_stack_set.this.name
}

output "permission_model" {
  description = "SELF_MANAGED or SERVICE_MANAGED, derived from the permission_model branch that was set."
  value       = local.permission_model
}

output "stack_instances" {
  description = "Stack instances keyed like stack_instances (\"<target>/<region>\"): id (the provider's instance ID), region, organizational_unit_id (null for self_managed), account_ids (the one target account for self_managed; every account the OU deployment reached for service_managed), and stack_ids (the instance stack ARNs in those accounts)."
  value = {
    for key, instance in aws_cloudformation_stack_set_instance.this : key => {
      id                     = instance.id
      region                 = local.stack_instances[key].region
      organizational_unit_id = local.self_managed ? null : local.stack_instances[key].target
      account_ids            = local.self_managed ? [local.stack_instances[key].target] : [for summary in instance.stack_instance_summaries : summary.account_id]
      stack_ids              = local.self_managed ? [instance.stack_id] : [for summary in instance.stack_instance_summaries : summary.stack_id]
    }
  }
}
