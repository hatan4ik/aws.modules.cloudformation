# Every variable validation, each with a failing run. Passing counterparts
# live in the behaviour files.

mock_provider "aws" {}

variables {
  role = {
    administration = {
      account_id = "111111111111"
    }
  }
}

run "rejects_neither_branch" {
  command = plan

  variables {
    role = {}
  }

  expect_failures = [var.role]
}

run "rejects_both_branches" {
  command = plan

  variables {
    role = {
      administration = { account_id = "111111111111" }
      execution      = { administration_role_arns = ["arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"] }
    }
  }

  expect_failures = [var.role]
}

run "rejects_a_short_account_id" {
  command = plan

  variables {
    role = {
      administration = { account_id = "11111111111" }
    }
  }

  expect_failures = [var.role]
}

run "rejects_an_administration_role_name_with_a_path" {
  command = plan

  variables {
    role = {
      administration = { account_id = "111111111111", name = "stacksets/admin" }
    }
  }

  expect_failures = [var.role]
}

run "rejects_an_execution_role_name_over_64_characters" {
  command = plan

  variables {
    role = {
      administration = { account_id = "111111111111", execution_role_name = format("%065d", 0) }
    }
  }

  expect_failures = [var.role]
}

run "rejects_an_empty_target_account_set" {
  command = plan

  variables {
    role = {
      administration = { account_id = "111111111111", target_account_ids = [] }
    }
  }

  expect_failures = [var.role]
}

run "rejects_a_malformed_target_account" {
  command = plan

  variables {
    role = {
      administration = { account_id = "111111111111", target_account_ids = ["22222222222a"] }
    }
  }

  expect_failures = [var.role]
}

run "rejects_a_malformed_opt_in_region" {
  command = plan

  variables {
    role = {
      administration = { account_id = "111111111111", opt_in_regions = ["Hong Kong"] }
    }
  }

  expect_failures = [var.role]
}

run "rejects_no_trusted_administration_role" {
  command = plan

  variables {
    role = {
      execution = { administration_role_arns = [] }
    }
  }

  expect_failures = [var.role]
}

run "rejects_an_account_root_as_administration_role" {
  command = plan

  variables {
    role = {
      execution = { administration_role_arns = ["arn:aws:iam::111111111111:root"] }
    }
  }

  expect_failures = [var.role]
}

run "rejects_an_execution_role_name_with_a_path" {
  command = plan

  variables {
    role = {
      execution = {
        administration_role_arns = ["arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"]
        name                     = "stacksets/execution"
      }
    }
  }

  expect_failures = [var.role]
}

run "rejects_a_policy_arn_that_is_not_a_managed_policy" {
  command = plan

  variables {
    role = {
      execution = {
        administration_role_arns = ["arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"]
        policy_arns              = { wrong = "arn:aws:iam::111111111111:role/not-a-policy" }
      }
    }
  }

  expect_failures = [var.role]
}

run "rejects_an_inline_policy_that_is_not_json" {
  command = plan

  variables {
    role = {
      execution = {
        administration_role_arns = ["arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"]
        inline_policy            = "Version: 2012-10-17"
      }
    }
  }

  expect_failures = [var.role]
}

run "rejects_an_inline_policy_without_statement" {
  command = plan

  variables {
    role = {
      execution = {
        administration_role_arns = ["arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"]
        inline_policy            = "{\"Version\":\"2012-10-17\"}"
      }
    }
  }

  expect_failures = [var.role]
}

run "rejects_an_inline_policy_over_the_role_quota" {
  command = plan

  variables {
    role = {
      execution = {
        administration_role_arns = ["arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"]
        # 10,141 characters without whitespace: one over the budget.
        inline_policy = format("{\"Statement\":[],\"Sid\":\"%010116d\"}", 0)
      }
    }
  }

  expect_failures = [var.role]
}

run "accepts_an_inline_policy_at_the_role_quota" {
  command = plan

  variables {
    role = {
      execution = {
        administration_role_arns = ["arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"]
        # Exactly 10,140 characters without whitespace, plus whitespace IAM ignores.
        inline_policy = format("{ \"Statement\": [ ], \"Sid\": \"%010115d\" }", 0)
      }
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.execution_template) == 1
    error_message = "A policy at the budget, with whitespace that IAM does not count, must be accepted."
  }
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
    tags = { "AWS:owner" = "platform" }
  }

  expect_failures = [var.tags]
}

run "rejects_a_tag_value_over_256" {
  command = plan

  variables {
    tags = { Owner = format("%257s", "x") }
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

run "accepts_an_empty_tag_value" {
  command = plan

  variables {
    tags = { Reviewed = "" }
  }

  assert {
    condition     = aws_iam_role.administration[0].tags == tomap({ Name = "AWSCloudFormationStackSetAdministrationRole", Reviewed = "" })
    error_message = "IAM accepts an empty tag value, so the module must too."
  }
}
