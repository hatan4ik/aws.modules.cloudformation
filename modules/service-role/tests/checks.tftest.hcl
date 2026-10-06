mock_provider "aws" {}

variables {
  name       = "cloudformation-artifacts"
  account_id = "123456789012"
  statements = {
    SsmParameter = {
      actions   = ["ssm:PutParameter"]
      resources = ["arn:aws:ssm:us-east-1:123456789012:parameter/artifacts/*"]
    }
  }
}

run "warns_when_a_statement_allows_every_action" {
  command = plan

  variables {
    statements = {
      Everything = { actions = ["*"], resources = ["*"] }
    }
  }

  expect_failures = [check.statement_allows_every_action]
}

run "is_silent_for_a_deny_of_every_action" {
  command = plan

  variables {
    statements = {
      SsmParameter = { actions = ["ssm:PutParameter"], resources = ["arn:aws:ssm:us-east-1:123456789012:parameter/artifacts/*"] }
      DenyOutsideRegion = {
        effect     = "Deny"
        actions    = ["*"]
        resources  = ["*"]
        conditions = [{ test = "StringNotEquals", variable = "aws:RequestedRegion", values = ["us-east-1"] }]
      }
    }
  }

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.template.policy).Statement) == 2
    error_message = "A Deny of every action narrows the role and must not warn."
  }
}

run "warns_when_pass_role_names_every_role" {
  command = plan

  variables {
    pass_roles = {
      AnyRole = { role_arns = ["arn:aws:iam::123456789012:role/*"], services = ["lambda.amazonaws.com"] }
    }
  }

  expect_failures = [check.pass_role_to_any_role]
}

run "is_silent_for_a_prefixed_pass_role" {
  command = plan

  variables {
    pass_roles = {
      StackRoles = { role_arns = ["arn:aws:iam::123456789012:role/artifacts-*", "arn:aws:iam::123456789012:role/cloudformation/*"], services = ["lambda.amazonaws.com"] }
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.pass_role) == 1
    error_message = "A role prefix or a path is scoped and must not warn."
  }
}
