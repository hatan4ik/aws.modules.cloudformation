# Every variable validation and the policy-size precondition, each with a
# failing run. Passing counterparts live in the behaviour files.

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

run "rejects_a_name_with_a_slash" {
  command = plan

  variables {
    name = "cloudformation/artifacts"
  }

  expect_failures = [var.name]
}

run "rejects_a_name_over_64_characters" {
  command = plan

  variables {
    name = format("%065d", 0)
  }

  expect_failures = [var.name]
}

run "rejects_a_path_without_trailing_slash" {
  command = plan

  variables {
    path = "/cloudformation"
  }

  expect_failures = [var.path]
}

run "rejects_a_path_with_a_space" {
  command = plan

  variables {
    path = "/cloud formation/"
  }

  expect_failures = [var.path]
}

run "rejects_a_description_over_1000" {
  command = plan

  variables {
    description = format("%1001s", "x")
  }

  expect_failures = [var.description]
}

run "rejects_a_description_outside_latin1" {
  command = plan

  variables {
    description = "Deploys \u2603 stacks"
  }

  expect_failures = [var.description]
}

run "rejects_a_short_account_id" {
  command = plan

  variables {
    account_id = "12345678901"
  }

  expect_failures = [var.account_id]
}

run "rejects_no_statement" {
  command = plan

  variables {
    statements = {}
  }

  expect_failures = [var.statements]
}

run "rejects_a_sid_with_a_dash" {
  command = plan

  variables {
    statements = { "Ssm-Parameter" = { actions = ["ssm:PutParameter"], resources = ["*"] } }
  }

  expect_failures = [var.statements]
}

run "rejects_an_unknown_effect" {
  command = plan

  variables {
    statements = { Ssm = { effect = "allow", actions = ["ssm:PutParameter"], resources = ["*"] } }
  }

  expect_failures = [var.statements]
}

run "rejects_empty_actions" {
  command = plan

  variables {
    statements = { Ssm = { actions = [], resources = ["*"] } }
  }

  expect_failures = [var.statements]
}

run "rejects_empty_resources" {
  command = plan

  variables {
    statements = { Ssm = { actions = ["ssm:PutParameter"], resources = [] } }
  }

  expect_failures = [var.statements]
}

run "rejects_a_duplicate_condition_pair" {
  command = plan

  variables {
    statements = { Ssm = { actions = ["ssm:PutParameter"], resources = ["*"], conditions = [{ test = "StringEquals", variable = "aws:RequestedRegion", values = ["us-east-1"] }, { test = "StringEquals", variable = "aws:RequestedRegion", values = ["eu-west-1"] }] } }
  }

  expect_failures = [var.statements]
}

run "rejects_an_action_without_a_service" {
  command = plan

  variables {
    statements = { Ssm = { actions = ["PutParameter"], resources = ["*"] } }
  }

  expect_failures = [var.statements]
}

run "rejects_a_condition_without_values" {
  command = plan

  variables {
    statements = { Ssm = { actions = ["ssm:PutParameter"], resources = ["*"], conditions = [{ test = "StringEquals", variable = "aws:RequestedRegion", values = [] }] } }
  }

  expect_failures = [var.statements]
}

run "rejects_a_pass_role_without_services" {
  command = plan

  variables {
    pass_roles = { Fn = { role_arns = ["arn:aws:iam::123456789012:role/fn"], services = [] } }
  }

  expect_failures = [var.pass_roles]
}

run "rejects_a_pass_role_without_roles" {
  command = plan

  variables {
    pass_roles = { Fn = { role_arns = [], services = ["lambda.amazonaws.com"] } }
  }

  expect_failures = [var.pass_roles]
}

run "rejects_a_pass_role_on_any_account" {
  command = plan

  variables {
    pass_roles = { Fn = { role_arns = ["arn:aws:iam::*:role/fn"], services = ["lambda.amazonaws.com"] } }
  }

  expect_failures = [var.pass_roles]
}

run "rejects_a_bare_wildcard_pass_role" {
  command = plan

  variables {
    pass_roles = { Fn = { role_arns = ["*"], services = ["lambda.amazonaws.com"] } }
  }

  expect_failures = [var.pass_roles]
}

run "rejects_a_wildcard_service" {
  command = plan

  variables {
    pass_roles = { Fn = { role_arns = ["arn:aws:iam::123456789012:role/fn"], services = ["*.amazonaws.com"] } }
  }

  expect_failures = [var.pass_roles]
}

run "rejects_a_boundary_that_is_a_role" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::123456789012:role/boundary"
  }

  expect_failures = [var.permissions_boundary_arn]
}

run "rejects_too_many_tags" {
  command = plan

  variables {
    tags = { for i in range(50) : "key${i}" => "value" }
  }

  expect_failures = [var.tags]
}

run "rejects_an_aws_prefixed_tag" {
  command = plan

  variables {
    tags = { "aws:owner" = "platform" }
  }

  expect_failures = [var.tags]
}

run "rejects_a_tag_with_an_invalid_character" {
  command = plan

  variables {
    tags = { "Owner#1" = "platform" }
  }

  expect_failures = [var.tags]
}

run "rejects_inline_policies_over_the_role_quota" {
  command = plan

  variables {
    # One resource ARN long enough that the rendered policies exceed 10,240
    # characters without whitespace.
    statements = {
      SsmParameter = { actions = ["ssm:PutParameter"], resources = ["arn:aws:ssm:us-east-1:123456789012:parameter/${format("%010200d", 0)}"] }
    }
  }

  expect_failures = [aws_iam_role_policy.template]
}

run "accepts_an_empty_tag_value_and_a_latin1_description" {
  command = plan

  variables {
    tags        = { Reviewed = "" }
    description = "Déploie la pile d'artefacts."
  }

  assert {
    condition     = aws_iam_role.this.tags == tomap({ Name = "cloudformation-artifacts", Reviewed = "" }) && aws_iam_role.this.description == "Déploie la pile d'artefacts."
    error_message = "IAM accepts an empty tag value and Latin-1 descriptions, so the module must too."
  }
}
