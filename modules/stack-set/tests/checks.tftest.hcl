mock_provider "aws" {}

variables {
  name     = "baseline-config"
  template = { url = "https://baseline-templates.s3.amazonaws.com/config.yaml?versionId=Kq2c8eTP" }

  permission_model = {
    self_managed = {
      administration_role_arn = "arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"
    }
  }

  stack_instances = {
    "222222222222/us-east-1" = {}
  }
}

run "warns_when_no_instance_is_declared" {
  command = plan

  variables {
    stack_instances = {}
  }

  expect_failures = [check.no_stack_instances]
}

run "warns_when_strict_mode_caps_concurrency" {
  command = plan

  variables {
    operation_preferences = { failure_tolerance_count = 1, max_concurrent_count = 5 }
  }

  expect_failures = [check.max_concurrency_capped_by_failure_tolerance]
}

run "is_silent_at_the_strict_mode_bound" {
  command = plan

  variables {
    operation_preferences = { failure_tolerance_count = 4, max_concurrent_count = 5, concurrency_mode = "STRICT_FAILURE_TOLERANCE" }
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.operation_preferences[0].max_concurrent_count == 5
    error_message = "max_concurrent_count = failure_tolerance_count + 1 is fully effective and must not warn."
  }
}

run "is_silent_under_soft_failure_tolerance" {
  command = plan

  variables {
    operation_preferences = { failure_tolerance_count = 0, max_concurrent_count = 10, concurrency_mode = "SOFT_FAILURE_TOLERANCE" }
  }

  assert {
    condition     = aws_cloudformation_stack_set_instance.this["222222222222/us-east-1"].operation_preferences[0].concurrency_mode == "SOFT_FAILURE_TOLERANCE"
    error_message = "SOFT_FAILURE_TOLERANCE decouples concurrency from tolerance and must not warn."
  }
}
