mock_provider "aws" {}

variables {
  role = {
    execution = {
      administration_role_arns = ["arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"]
    }
  }
}

run "warns_when_the_execution_role_gets_administrator_access" {
  command = plan

  variables {
    role = {
      execution = {
        administration_role_arns = ["arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"]
        policy_arns              = { admin = "arn:aws:iam::aws:policy/AdministratorAccess" }
      }
    }
  }

  expect_failures = [check.execution_role_administrator_access]
}

run "is_silent_for_scoped_policies" {
  command = plan

  variables {
    role = {
      execution = {
        administration_role_arns = ["arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"]
        policy_arns              = { readonly = "arn:aws:iam::aws:policy/ReadOnlyAccess", custom = "arn:aws:iam::222222222222:policy/AdministratorAccessScoped" }
      }
    }
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.execution) == 2
    error_message = "Scoped policies must attach without a warning."
  }
}

run "is_silent_for_an_administration_role" {
  command = plan

  variables {
    role = {
      administration = { account_id = "111111111111" }
    }
  }

  assert {
    condition     = length(aws_iam_role.administration) == 1
    error_message = "The check must not fire for an administration call."
  }
}
