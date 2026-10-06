locals {
  # The module adds only a Name tag, and a caller's Name wins.
  tags = merge({ Name = var.name }, var.tags)

  # Only CloudFormation may assume the role. The conditions are the
  # confused-deputy mitigation modules/self-managed-roles uses, with two
  # deliberate differences (docs/DESIGN.md D15): AWS documents these keys for
  # StackSets, registry, and Git sync roles, not for a stack service role, so
  # the IfExists operators make them bind when CloudFormation supplies the
  # keys and leave the role assumable, as AWS's documented plain trust policy
  # is, when it does not; and aws:SourceArn is any CloudFormation resource of
  # this account (AWS's own wildcard example), because the ARN CloudFormation
  # would report (stack, change set) is not documented for this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudformation.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEqualsIfExists = { "aws:SourceAccount" = var.account_id }
        ArnLikeIfExists      = { "aws:SourceArn" = "arn:*:cloudformation:*:${var.account_id}:*" }
      }
    }]
  })

  # The caller's statements, rendered in Sid order with sorted lists so the
  # document is stable. Conditions with the same test are merged under it.
  template_statements = [
    for sid in sort(keys(var.statements)) : merge(
      {
        Sid      = sid
        Effect   = var.statements[sid].effect
        Action   = sort(tolist(var.statements[sid].actions))
        Resource = sort(tolist(var.statements[sid].resources))
      },
      length(var.statements[sid].conditions) == 0 ? {} : {
        Condition = {
          for test in distinct([for condition in var.statements[sid].conditions : condition.test]) : test => {
            for condition in var.statements[sid].conditions : condition.variable => sort(tolist(condition.values)) if condition.test == test
          }
        }
      },
    )
  ]

  template_policy = jsonencode({ Version = "2012-10-17", Statement = local.template_statements })

  # iam:PassRole on named roles, only to named services: AWS's recommended
  # scoping (Resource = the roles, iam:PassedToService = the services).
  pass_role_policy = length(var.pass_roles) == 0 ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [
      for sid in sort(keys(var.pass_roles)) : {
        Sid       = sid
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = sort(tolist(var.pass_roles[sid].role_arns))
        Condition = { StringEquals = { "iam:PassedToService" = sort(tolist(var.pass_roles[sid].services)) } }
      }
    ]
  })

  # IAM limits the aggregate size of a role's inline policies to 10,240
  # characters, not counting whitespace; neither does this.
  inline_policy_size = length(replace(local.template_policy, "/\\s/", "")) + (local.pass_role_policy == null ? 0 : length(replace(local.pass_role_policy, "/\\s/", "")))
}
