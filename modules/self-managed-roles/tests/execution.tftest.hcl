# The execution branch, compared with AWS's sample template
# AWSCloudFormationStackSetExecutionRole.yml and the guide's minimum policy.

mock_provider "aws" {}

variables {
  role = {
    execution = {
      administration_role_arns = ["arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"]
    }
  }
}

run "renders_a_minimum_execution_role" {
  command = plan

  assert {
    condition     = length(aws_iam_role.execution) == 1 && length(aws_iam_role.administration) == 0 && length(aws_iam_role_policy.administration) == 0
    error_message = "An execution call must create exactly the execution role and nothing of the administration branch."
  }

  assert {
    condition     = aws_iam_role.execution[0].name == "AWSCloudFormationStackSetExecutionRole"
    error_message = "The role name must default to the one StackSets uses when execution_role_name is not given."
  }

  assert {
    condition = jsondecode(aws_iam_role.execution[0].assume_role_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { AWS = ["arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"] }
        Action    = "sts:AssumeRole"
      }]
    }
    error_message = "The trust policy must name the administration role, not the whole administrator account."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.execution_cloudformation[0].policy) == {
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = "cloudformation:*", Resource = "*" }]
    }
    error_message = "The execution role must always carry cloudformation:*, the minimum AWS documents."
  }

  assert {
    condition     = length(aws_iam_role_policy.execution_template) == 0 && length(aws_iam_role_policy_attachment.execution) == 0
    error_message = "Nothing beyond the minimum may be attached by default; AWS's sample AdministratorAccess in particular must not be."
  }

  assert {
    condition     = aws_iam_role.execution[0].tags == tomap({ Name = "AWSCloudFormationStackSetExecutionRole" })
    error_message = "The module must add exactly one tag by default: Name = the role name."
  }
}

run "adds_the_template_permissions_the_caller_grants" {
  command = plan

  variables {
    role = {
      execution = {
        name = "baseline-stackset-execution"
        administration_role_arns = [
          "arn:aws:iam::111111111111:role/stacksets/baseline-admin",
          "arn:aws:iam::444444444444:role/AWSCloudFormationStackSetAdministrationRole",
        ]
        policy_arns = {
          config = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
          custom = "arn:aws:iam::222222222222:policy/baseline-extra"
        }
        inline_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"ssm:PutParameter\",\"Resource\":\"*\"}]}"
      }
    }
  }

  assert {
    condition     = aws_iam_role.execution[0].name == "baseline-stackset-execution"
    error_message = "A custom execution role name must pass through."
  }

  assert {
    condition     = jsondecode(aws_iam_role.execution[0].assume_role_policy).Statement[0].Principal.AWS == ["arn:aws:iam::111111111111:role/stacksets/baseline-admin", "arn:aws:iam::444444444444:role/AWSCloudFormationStackSetAdministrationRole"]
    error_message = "Every administration role ARN must be trusted, in a stable order."
  }

  assert {
    condition     = aws_iam_role_policy.execution_template[0].name == "StackSetsTemplate" && aws_iam_role_policy.execution_template[0].policy == "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"ssm:PutParameter\",\"Resource\":\"*\"}]}"
    error_message = "inline_policy must be attached unchanged as its own inline policy."
  }

  assert {
    condition     = toset(keys(aws_iam_role_policy_attachment.execution)) == toset(["config", "custom"]) && aws_iam_role_policy_attachment.execution["custom"].policy_arn == "arn:aws:iam::222222222222:policy/baseline-extra" && aws_iam_role_policy_attachment.execution["config"].role == "baseline-stackset-execution"
    error_message = "Each policy_arns entry must become one attachment keyed by its label."
  }

  assert {
    condition     = length(aws_iam_role_policy.execution_cloudformation) == 1
    error_message = "The cloudformation:* minimum must stay alongside caller policies."
  }
}
