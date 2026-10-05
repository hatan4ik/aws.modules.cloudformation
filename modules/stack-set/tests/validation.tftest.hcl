# Every variable validation and precondition, each with a failing run. Passing
# counterparts live in the behaviour files.

mock_provider "aws" {}

variables {
  name     = "baseline-config"
  template = { url = "https://baseline-templates.s3.amazonaws.com/config.yaml" }

  permission_model = {
    self_managed = {
      administration_role_arn = "arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"
    }
  }

  stack_instances = {
    "222222222222/us-east-1" = {}
  }
}

run "rejects_name_starting_with_a_digit" {
  command = plan

  variables {
    name = "9baseline"
  }

  expect_failures = [var.name]
}

run "rejects_name_with_a_dot" {
  command = plan

  variables {
    name = "baseline.config"
  }

  expect_failures = [var.name]
}

run "rejects_empty_description" {
  command = plan

  variables {
    description = ""
  }

  expect_failures = [var.description]
}

run "rejects_description_over_1024" {
  command = plan

  variables {
    description = format("%1025s", "x")
  }

  expect_failures = [var.description]
}

run "rejects_template_with_neither" {
  command = plan

  variables {
    template = {}
  }

  expect_failures = [var.template]
}

run "rejects_template_with_both" {
  command = plan

  variables {
    template = { body = "{}", url = "https://bucket.s3.amazonaws.com/t.yaml" }
  }

  expect_failures = [var.template]
}

run "rejects_template_body_over_51200_bytes" {
  command = plan

  variables {
    template = { body = "{\"Description\":\"é${format("%51181s", "")}\"}" }
  }

  expect_failures = [var.template]
}

run "rejects_non_s3_template_url" {
  command = plan

  variables {
    template = { url = "https://raw.githubusercontent.com/org/repo/main/t.yaml" }
  }

  expect_failures = [var.template]
}

run "rejects_s3_website_template_url" {
  command = plan

  variables {
    template = { url = "https://bucket.s3-website-us-east-1.amazonaws.com/template.yaml" }
  }

  expect_failures = [var.template]
}

run "rejects_s3_website_dot_region_template_url" {
  command = plan

  variables {
    template = { url = "https://bucket.s3-website.eu-west-1.amazonaws.com/template.yaml" }
  }

  expect_failures = [var.template]
}

run "accepts_s3_website_in_the_object_key" {
  command = plan

  # The website check reads the host only, not the object key.
  variables {
    template = { url = "https://bucket.s3.us-east-1.amazonaws.com/templates/s3-website.yaml" }
  }
}

run "rejects_more_than_200_parameters" {
  command = plan

  variables {
    parameters = { for i in range(201) : "P${i}" => "v" }
  }

  expect_failures = [var.parameters]
}

run "rejects_non_alphanumeric_parameter_name" {
  command = plan

  variables {
    parameters = { "retention_days" = "30" }
  }

  expect_failures = [var.parameters]
}

run "rejects_parameter_value_over_4096" {
  command = plan

  variables {
    parameters = { Big = format("%4097s", "") }
  }

  expect_failures = [var.parameters]
}

run "rejects_unknown_capability" {
  command = plan

  variables {
    capabilities = ["CAPABILITY_ADMIN"]
  }

  expect_failures = [var.capabilities]
}

run "rejects_neither_permission_model" {
  command = plan

  variables {
    permission_model = {}
  }

  expect_failures = [var.permission_model]
}

run "rejects_both_permission_models" {
  command = plan

  variables {
    permission_model = {
      self_managed    = { administration_role_arn = "arn:aws:iam::111111111111:role/admin" }
      service_managed = { auto_deployment = { enabled = true } }
    }
  }

  expect_failures = [var.permission_model]
}

run "rejects_non_role_administration_arn" {
  command = plan

  variables {
    permission_model = { self_managed = { administration_role_arn = "arn:aws:iam::111111111111:policy/admin" } }
  }

  expect_failures = [var.permission_model]
}

run "rejects_execution_role_with_path" {
  command = plan

  variables {
    permission_model = { self_managed = { administration_role_arn = "arn:aws:iam::111111111111:role/admin", execution_role_name = "stacksets/exec" } }
  }

  expect_failures = [var.permission_model]
}

run "rejects_execution_role_over_64" {
  command = plan

  variables {
    permission_model = { self_managed = { administration_role_arn = "arn:aws:iam::111111111111:role/admin", execution_role_name = format("%065d", 0) } }
  }

  expect_failures = [var.permission_model]
}

run "rejects_unknown_call_as" {
  command = plan

  variables {
    permission_model = { service_managed = { auto_deployment = { enabled = true }, call_as = "MANAGEMENT" } }
  }

  expect_failures = [var.permission_model]
}

run "rejects_instance_key_without_region" {
  command = plan

  variables {
    stack_instances = { "222222222222" = {} }
  }

  expect_failures = [var.stack_instances]
}

run "rejects_instance_key_with_short_account" {
  command = plan

  variables {
    stack_instances = { "2222/us-east-1" = {} }
  }

  expect_failures = [var.stack_instances]
}

run "rejects_instance_key_with_bad_region" {
  command = plan

  variables {
    stack_instances = { "222222222222/useast1" = {} }
  }

  expect_failures = [var.stack_instances]
}

run "rejects_instance_key_with_bad_ou" {
  command = plan

  variables {
    stack_instances = { "ou-ab/us-east-1" = {} }
  }

  expect_failures = [var.stack_instances]
}

run "rejects_bad_parameter_override_name" {
  command = plan

  variables {
    stack_instances = { "222222222222/us-east-1" = { parameter_overrides = { "Retention-Days" = "30" } } }
  }

  expect_failures = [var.stack_instances]
}

run "rejects_both_failure_tolerance_forms" {
  command = plan

  variables {
    operation_preferences = { failure_tolerance_count = 1, failure_tolerance_percentage = 10 }
  }

  expect_failures = [var.operation_preferences]
}

run "rejects_both_max_concurrent_forms" {
  command = plan

  variables {
    operation_preferences = { max_concurrent_count = 1, max_concurrent_percentage = 10 }
  }

  expect_failures = [var.operation_preferences]
}

run "rejects_negative_failure_tolerance" {
  command = plan

  variables {
    operation_preferences = { failure_tolerance_count = -1 }
  }

  expect_failures = [var.operation_preferences]
}

run "rejects_failure_tolerance_percentage_over_100" {
  command = plan

  variables {
    operation_preferences = { failure_tolerance_percentage = 101 }
  }

  expect_failures = [var.operation_preferences]
}

run "rejects_zero_max_concurrent_count" {
  command = plan

  variables {
    operation_preferences = { max_concurrent_count = 0 }
  }

  expect_failures = [var.operation_preferences]
}

run "rejects_zero_max_concurrent_percentage" {
  command = plan

  variables {
    operation_preferences = { max_concurrent_percentage = 0 }
  }

  expect_failures = [var.operation_preferences]
}

run "rejects_fractional_max_concurrent_count" {
  command = plan

  variables {
    operation_preferences = { max_concurrent_count = 2.5 }
  }

  expect_failures = [var.operation_preferences]
}

run "rejects_unknown_concurrency_mode" {
  command = plan

  variables {
    operation_preferences = { concurrency_mode = "BEST_EFFORT" }
  }

  expect_failures = [var.operation_preferences]
}

run "rejects_unknown_region_concurrency_type" {
  command = plan

  variables {
    operation_preferences = { region_concurrency_type = "ROLLING" }
  }

  expect_failures = [var.operation_preferences]
}

run "rejects_malformed_region_order" {
  command = plan

  variables {
    operation_preferences = { region_order = ["us-east-1", "Europe"] }
  }

  expect_failures = [var.operation_preferences]
}

run "rejects_duplicate_region_order" {
  command = plan

  variables {
    operation_preferences = { region_order = ["us-east-1", "us-east-1"] }
  }

  expect_failures = [var.operation_preferences]
}

run "rejects_more_than_50_tags_including_name" {
  command = plan

  variables {
    tags = { for i in range(50) : "k${i}" => "v" }
  }

  expect_failures = [var.tags]
}

run "rejects_reserved_aws_tag_prefix" {
  command = plan

  variables {
    tags = { "AWS:owner" = "x" }
  }

  expect_failures = [var.tags]
}

run "rejects_malformed_timeout" {
  command = plan

  variables {
    timeouts = { stack_set_update = "two hours" }
  }

  expect_failures = [var.timeouts]
}

run "rejects_ou_targets_for_self_managed" {
  command = plan

  variables {
    stack_instances = {
      "222222222222/us-east-1"     = {}
      "ou-ab12-11111111/us-east-1" = {}
    }
  }

  expect_failures = [aws_cloudformation_stack_set.this]
}

run "rejects_account_targets_for_service_managed" {
  command = plan

  variables {
    permission_model = { service_managed = { auto_deployment = { enabled = true } } }
    stack_instances = {
      "ou-ab12-11111111/us-east-1" = {}
      "222222222222/us-east-1"     = {}
    }
  }

  expect_failures = [aws_cloudformation_stack_set.this]
}

run "rejects_auto_expand_for_service_managed" {
  command = plan

  variables {
    permission_model = { service_managed = { auto_deployment = { enabled = true } } }
    stack_instances  = { "ou-ab12-11111111/us-east-1" = {} }
    capabilities     = ["CAPABILITY_IAM", "CAPABILITY_AUTO_EXPAND"]
  }

  expect_failures = [aws_cloudformation_stack_set.this]
}

run "accepts_boundary_values" {
  command = plan

  variables {
    name        = "a"
    description = format("%1024s", "x")
    parameters  = { for i in range(200) : "P${i}" => "v" }
    tags        = { for i in range(49) : "k${i}" => "v" }
    operation_preferences = {
      failure_tolerance_percentage = 100
      max_concurrent_percentage    = 100
    }
    permission_model = {
      self_managed = {
        administration_role_arn = "arn:aws-us-gov:iam::111111111111:role/admin"
        execution_role_name     = format("%064d", 0)
      }
    }
    stack_instances = { "222222222222/us-gov-west-1" = {} }
  }

  assert {
    condition     = length(aws_cloudformation_stack_set.this.parameters) == 200 && length(aws_cloudformation_stack_set.this.tags) == 50 && aws_cloudformation_stack_set_instance.this["222222222222/us-gov-west-1"].stack_set_instance_region == "us-gov-west-1"
    error_message = "Documented maximums, a GovCloud partition and region, and a 64-character execution role must be accepted."
  }
}
