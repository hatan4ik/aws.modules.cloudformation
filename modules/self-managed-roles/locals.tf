locals {
  administration = var.role.administration
  execution      = var.role.execution

  role_name = local.administration != null ? local.administration.name : local.execution.name

  # The module adds only a Name tag, and a caller's Name wins.
  tags = merge({ Name = local.role_name }, var.tags)

  # Administration role: AWS's sample template
  # (AWSCloudFormationStackSetAdministrationRole.yml) trusts
  # cloudformation.amazonaws.com. Regions disabled by default have their own
  # regional service principal, which must be trusted too. The conditions are
  # AWS's documented confused-deputy mitigation: only StackSets of this
  # account may make CloudFormation assume the role.
  administration_assume_role_policy = local.administration == null ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = concat(
          ["cloudformation.amazonaws.com"],
          [for region in sort(local.administration.opt_in_regions) : "cloudformation.${region}.amazonaws.com"],
        )
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.administration.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:*:cloudformation:*:${local.administration.account_id}:stackset/*" }
      }
    }]
  })

  # The sample's one permission: assume the execution role, by name, in any
  # account, or only in target_account_ids when set.
  administration_policy = local.administration == null ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Resource = local.administration.target_account_ids == null ? ["arn:*:iam::*:role/${local.administration.execution_role_name}"] : [
        for account_id in sort(local.administration.target_account_ids) : "arn:*:iam::${account_id}:role/${local.administration.execution_role_name}"
      ]
    }]
  })

  # Execution role: AWS's sample (AWSCloudFormationStackSetExecutionRole.yml)
  # trusts the whole administrator account (its root principal). The module
  # trusts the administration role ARNs instead, the narrower form AWS
  # documents for customized administration roles: no other principal in the
  # administrator account can assume it.
  execution_assume_role_policy = local.execution == null ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = sort(local.execution.administration_role_arns) }
      Action    = "sts:AssumeRole"
    }]
  })

  # The minimum AWS documents for an execution role: StackSets creates,
  # updates, describes, and deletes the instance stack with it.
  execution_cloudformation_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "cloudformation:*"
      Resource = "*"
    }]
  })
}
