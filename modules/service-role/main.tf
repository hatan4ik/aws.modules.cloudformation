# One CloudFormation stack service role per call: trusted only by
# CloudFormation, with exactly the caller's statements and pass-role grants.
resource "aws_iam_role" "this" {
  name                 = var.name
  path                 = var.path
  description          = coalesce(var.description, "CloudFormation service role: assumed by CloudFormation to create, update, and delete the resources of the stacks that use it.")
  assume_role_policy   = local.assume_role_policy
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

resource "aws_iam_role_policy" "template" {
  name   = "CloudFormationTemplate"
  role   = aws_iam_role.this.id
  policy = local.template_policy

  lifecycle {
    precondition {
      condition     = local.inline_policy_size <= 10240
      error_message = "statements and pass_roles render to ${local.inline_policy_size} characters without whitespace, over IAM's 10,240-character limit for a role's inline policies. Merge statements that share resources, or use wildcards within one service's actions."
    }
  }
}

resource "aws_iam_role_policy" "pass_role" {
  count = local.pass_role_policy == null ? 0 : 1

  name   = "CloudFormationPassRole"
  role   = aws_iam_role.this.id
  policy = local.pass_role_policy
}
