output "role_arn" {
  description = "ARN of the service role, for the root module's iam_role_arn. It depends on the role's policies as well as the role, so a stack that uses it is created after its permissions exist and destroyed before they are removed."
  value       = aws_iam_role.this.arn

  # CloudFormation uses the role for every operation, including the delete.
  # Without this, a stack would depend on the role alone and could be created
  # before its policies, or outlive them on destroy.
  depends_on = [aws_iam_role_policy.template, aws_iam_role_policy.pass_role]
}

output "role_name" {
  description = "Name of the service role, for attaching further policies outside the module."
  value       = aws_iam_role.this.name
}

output "inline_policies" {
  description = "The role's inline policy documents as JSON, keyed by policy name: CloudFormationTemplate (the statements) and, when pass_roles is set, CloudFormationPassRole. For review, or for checking with IAM Access Analyzer's policy validation."
  value = merge(
    { (aws_iam_role_policy.template.name) = aws_iam_role_policy.template.policy },
    { for policy in aws_iam_role_policy.pass_role : policy.name => policy.policy },
  )
}
