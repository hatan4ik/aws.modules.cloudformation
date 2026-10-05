mock_provider "aws" {}

variables {
  name     = "baseline-config"
  template = { url = "https://baseline-templates.s3.amazonaws.com/config.yaml?versionId=Kq2c8eTP" }

  permission_model = {
    service_managed = {
      auto_deployment = { enabled = true }
    }
  }

  stack_instances = {
    "ou-ab12-11111111/us-east-1" = {}
  }
}

run "splits_preferences_between_the_stack_set_and_its_instances" {
  command = plan

  variables {
    operation_preferences = {
      failure_tolerance_percentage = 10
      max_concurrent_percentage    = 25
      concurrency_mode             = "SOFT_FAILURE_TOLERANCE"
      region_concurrency_type      = "SEQUENTIAL"
      region_order                 = ["us-east-1", "eu-west-1"]
    }
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.operation_preferences[0].failure_tolerance_percentage == 10 && aws_cloudformation_stack_set.this.operation_preferences[0].max_concurrent_percentage == 25
    error_message = "Account-level tolerance and concurrency must govern StackSet updates."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.operation_preferences[0].region_concurrency_type == "SEQUENTIAL" && aws_cloudformation_stack_set.this.operation_preferences[0].region_order == tolist(["us-east-1", "eu-west-1"])
    error_message = "Region ordering must govern StackSet updates, which span every region."
  }

  assert {
    condition     = aws_cloudformation_stack_set_instance.this["ou-ab12-11111111/us-east-1"].operation_preferences[0].failure_tolerance_percentage == 10 && aws_cloudformation_stack_set_instance.this["ou-ab12-11111111/us-east-1"].operation_preferences[0].max_concurrent_percentage == 25 && aws_cloudformation_stack_set_instance.this["ou-ab12-11111111/us-east-1"].operation_preferences[0].concurrency_mode == "SOFT_FAILURE_TOLERANCE"
    error_message = "Instances must apply the account-level settings and concurrency_mode to their own operations."
  }

  assert {
    condition     = aws_cloudformation_stack_set_instance.this["ou-ab12-11111111/us-east-1"].operation_preferences[0].region_order == null && aws_cloudformation_stack_set_instance.this["ou-ab12-11111111/us-east-1"].operation_preferences[0].region_concurrency_type == null
    error_message = "Region ordering must not be sent on a single-region instance operation."
  }
}

run "sends_counts_and_omits_unused_blocks" {
  command = plan

  variables {
    operation_preferences = {
      failure_tolerance_count = 2
      max_concurrent_count    = 3
    }
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.operation_preferences[0].failure_tolerance_count == 2 && aws_cloudformation_stack_set.this.operation_preferences[0].max_concurrent_count == 3 && aws_cloudformation_stack_set.this.operation_preferences[0].failure_tolerance_percentage == null
    error_message = "Counts must pass through and unset percentages must stay unset."
  }
}

run "region_only_preferences_reach_the_stack_set_alone" {
  command = plan

  variables {
    operation_preferences = { region_concurrency_type = "PARALLEL" }
  }

  assert {
    condition     = length(aws_cloudformation_stack_set.this.operation_preferences) == 1 && length(aws_cloudformation_stack_set_instance.this["ou-ab12-11111111/us-east-1"].operation_preferences) == 0
    error_message = "With only region settings, the StackSet gets a block and instances get none."
  }
}

run "concurrency_mode_only_reaches_instances_alone" {
  command = plan

  variables {
    operation_preferences = { concurrency_mode = "STRICT_FAILURE_TOLERANCE" }
  }

  assert {
    condition     = length(aws_cloudformation_stack_set.this.operation_preferences) == 0 && length(aws_cloudformation_stack_set_instance.this["ou-ab12-11111111/us-east-1"].operation_preferences) == 1
    error_message = "With only concurrency_mode, instances get a block and the StackSet, which has no such field, gets none."
  }
}
