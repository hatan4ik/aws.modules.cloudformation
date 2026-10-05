output "role_arn" {
  description = "ARN of the role this call created (administration or execution)."
  value       = local.administration != null ? aws_iam_role.administration[0].arn : aws_iam_role.execution[0].arn
}

output "role_name" {
  description = "Name of the role this call created (administration or execution)."
  value       = local.administration != null ? aws_iam_role.administration[0].name : aws_iam_role.execution[0].name
}

output "stack_set_permission_model" {
  description = "For an administration call: the value to pass as modules/stack-set's permission_model, { self_managed = { administration_role_arn, execution_role_name } }. The execution_role_name is the one this administration role may assume, so it always matches the role's policy. null for an execution call."
  value = local.administration == null ? null : {
    self_managed = {
      administration_role_arn = aws_iam_role.administration[0].arn
      execution_role_name     = local.administration.execution_role_name
    }
  }
}
