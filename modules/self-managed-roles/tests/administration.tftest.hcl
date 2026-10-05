# The administration branch, compared statement by statement with AWS's
# sample template AWSCloudFormationStackSetAdministrationRole.yml.

mock_provider "aws" {}

variables {
  role = {
    administration = {
      account_id = "111111111111"
    }
  }
}

run "renders_the_aws_sample_administration_role" {
  command = plan

  assert {
    condition     = length(aws_iam_role.administration) == 1 && length(aws_iam_role.execution) == 0
    error_message = "An administration call must create exactly the administration role and no execution role."
  }

  assert {
    condition     = aws_iam_role.administration[0].name == "AWSCloudFormationStackSetAdministrationRole"
    error_message = "The role name must default to the one StackSets falls back to."
  }

  assert {
    condition = jsondecode(aws_iam_role.administration[0].assume_role_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Service = ["cloudformation.amazonaws.com"] }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "aws:SourceAccount" = "111111111111" }
          ArnLike      = { "aws:SourceArn" = "arn:*:cloudformation:*:111111111111:stackset/*" }
        }
      }]
    }
    error_message = "The trust policy must let only cloudformation.amazonaws.com assume the role, and only for StackSets of this account (aws:SourceAccount and aws:SourceArn)."
  }

  assert {
    condition     = aws_iam_role_policy.administration[0].name == "AssumeRole-AWSCloudFormationStackSetExecutionRole"
    error_message = "The inline policy must keep the sample template's name."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.administration[0].policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = ["arn:*:iam::*:role/AWSCloudFormationStackSetExecutionRole"]
      }]
    }
    error_message = "By default the role may assume only the execution role, by name, in any account: the sample template's one permission."
  }

  assert {
    condition     = aws_iam_role.administration[0].tags == tomap({ Name = "AWSCloudFormationStackSetAdministrationRole" })
    error_message = "The module must add exactly one tag by default: Name = the role name."
  }

  assert {
    condition     = length(aws_iam_role_policy.execution_cloudformation) == 0 && length(aws_iam_role_policy.execution_template) == 0 && length(aws_iam_role_policy_attachment.execution) == 0
    error_message = "An administration call must create no execution-role policies."
  }
}

run "scopes_target_accounts_and_trusts_opt_in_regions" {
  command = plan

  variables {
    role = {
      administration = {
        account_id          = "111111111111"
        name                = "baseline-stackset-admin"
        execution_role_name = "baseline-stackset-execution"
        target_account_ids  = ["333333333333", "222222222222"]
        opt_in_regions      = ["me-south-1", "ap-east-1"]
      }
    }
    tags = { Name = "caller-chosen", Owner = "platform" }
  }

  assert {
    condition     = aws_iam_role.administration[0].name == "baseline-stackset-admin"
    error_message = "A custom role name must pass through."
  }

  assert {
    condition     = jsondecode(aws_iam_role.administration[0].assume_role_policy).Statement[0].Principal.Service == ["cloudformation.amazonaws.com", "cloudformation.ap-east-1.amazonaws.com", "cloudformation.me-south-1.amazonaws.com"]
    error_message = "Every opt-in Region's regional service principal must be trusted besides the global one, in a stable order."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.administration[0].policy).Statement[0].Resource == [
      "arn:*:iam::222222222222:role/baseline-stackset-execution",
      "arn:*:iam::333333333333:role/baseline-stackset-execution",
    ]
    error_message = "target_account_ids must narrow sts:AssumeRole to the execution role in exactly those accounts."
  }

  assert {
    condition     = aws_iam_role_policy.administration[0].name == "AssumeRole-baseline-stackset-execution"
    error_message = "The policy name must follow the execution role name, as in the sample template."
  }

  assert {
    condition     = aws_iam_role.administration[0].tags == tomap({ Name = "caller-chosen", Owner = "platform" })
    error_message = "A caller's Name tag must override the module's default."
  }
}
