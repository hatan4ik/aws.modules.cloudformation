# One CloudFormation stack per module call. Every cross-field rule the API
# enforces (template body XOR URL, stack policy body XOR URL, the capability
# enum, name and size limits) is a variable validation in variables.tf, so it
# fails at plan before this resource is evaluated.
resource "aws_cloudformation_stack" "this" {
  name = var.name

  template_body = var.template.body
  template_url  = var.template.url
  parameters    = var.parameters
  capabilities  = var.capabilities

  on_failure         = var.on_failure
  timeout_in_minutes = var.timeout_in_minutes
  notification_arns  = var.notification_arns

  policy_body = try(var.stack_policy.body, null)
  policy_url  = try(var.stack_policy.url, null)

  iam_role_arn = var.iam_role_arn

  tags = local.tags

  timeouts {
    create = var.timeouts.create
    update = var.timeouts.update
    delete = var.timeouts.delete
  }
}
