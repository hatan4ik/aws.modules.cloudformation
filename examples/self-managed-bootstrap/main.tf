# Administrator account: the credentials Terraform runs with. The StackSet and
# its administration role live here.
provider "aws" {
  region = var.region
}

# Target account: Terraform assumes a role there only to create the execution
# role. StackSets itself never uses this provider.
provider "aws" {
  alias  = "target"
  region = var.region

  assume_role {
    role_arn = var.target_account_role_arn
  }
}

data "aws_caller_identity" "administrator" {}

data "aws_partition" "current" {}

locals {
  # One name, used by both roles and by the StackSet: the administration
  # role's policy, the execution role, and the StackSet's execution_role_name
  # must all agree on it.
  execution_role_name = "AWSCloudFormationStackSetExecutionRole"
}

# Step 1, administrator account: the role CloudFormation assumes to reach the
# target accounts. target_account_ids narrows it to the accounts this
# StackSet deploys to; the AWS sample allows any account.
module "stack_set_administration_role" {
  source = "../../modules/self-managed-roles"

  role = {
    administration = {
      account_id          = data.aws_caller_identity.administrator.account_id
      execution_role_name = local.execution_role_name
      target_account_ids  = [var.target_account_id]
    }
  }

  tags = { Environment = "example", Owner = "platform" }
}

# Step 2, every target account: the role the administration role assumes to
# create the instance stack. It trusts that one role, not the whole
# administrator account, and gets only what parameter.yaml creates.
module "stack_set_execution_role" {
  source = "../../modules/self-managed-roles"

  providers = {
    aws = aws.target
  }

  role = {
    execution = {
      name                     = local.execution_role_name
      administration_role_arns = [module.stack_set_administration_role.role_arn]

      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect = "Allow"
          Action = [
            "ssm:PutParameter",
            "ssm:GetParameters",
            "ssm:DeleteParameter",
            "ssm:AddTagsToResource",
            "ssm:RemoveTagsFromResource",
            "ssm:ListTagsForResource",
          ]
          Resource = "arn:${data.aws_partition.current.partition}:ssm:*:${var.target_account_id}:parameter/stackset-bootstrap/*"
        }]
      })
    }
  }

  tags = { Environment = "example", Owner = "platform" }
}

# Step 3, administrator account: the StackSet. Its permission_model is the
# administration call's output, so the role ARN and execution role name
# cannot drift from the roles that exist.
module "parameter_baseline" {
  source = "../../modules/stack-set"

  name        = var.name
  description = "Self-managed StackSet bootstrapped from zero by modules/self-managed-roles"
  template    = { body = file("${path.module}/parameter.yaml") }
  parameters  = { Message = "deployed by ${var.name}" }

  permission_model = module.stack_set_administration_role.stack_set_permission_model

  stack_instances = {
    "${var.target_account_id}/${var.region}" = {}
  }

  tags = { Environment = "example", Owner = "platform" }

  # The instance is created by assuming the execution role, which nothing in
  # this module's inputs refers to: wait for it (and its policies) explicitly.
  depends_on = [module.stack_set_execution_role]
}
