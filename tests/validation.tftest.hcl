# Every variable validation, each with a failing run. Passing counterparts and
# boundary values live in defaults.tftest.hcl.

mock_provider "aws" {}

variables {
  name         = "vendor-agent"
  template     = { url = "https://vendor-templates.s3.us-east-1.amazonaws.com/agent.yaml" }
  iam_role_arn = "arn:aws:iam::123456789012:role/vendor-agent-deployer"
}

run "rejects_name_starting_with_a_digit" {
  command = plan

  variables {
    name = "1stack"
  }

  expect_failures = [var.name]
}

run "rejects_name_with_underscore" {
  command = plan

  variables {
    name = "vendor_agent"
  }

  expect_failures = [var.name]
}

run "rejects_name_longer_than_128" {
  command = plan

  variables {
    name = "a${format("%0128d", 0)}"
  }

  expect_failures = [var.name]
}

run "rejects_template_with_neither_body_nor_url" {
  command = plan

  variables {
    template = {}
  }

  expect_failures = [var.template]
}

run "rejects_template_with_both_body_and_url" {
  command = plan

  variables {
    template = { body = "{}", url = "https://bucket.s3.amazonaws.com/t.json" }
  }

  expect_failures = [var.template]
}

run "rejects_empty_template_body" {
  command = plan

  variables {
    template = { body = "" }
  }

  expect_failures = [var.template]
}

run "rejects_template_body_over_51200_bytes_counted_in_bytes" {
  command = plan

  variables {
    # 51,200 characters but 51,201 bytes: the multi-byte "é" tips it over.
    template = { body = "{\"Description\":\"é${format("%51181s", "")}\"}" }
  }

  expect_failures = [var.template]
}

run "rejects_non_s3_template_url" {
  command = plan

  variables {
    template = { url = "https://example.com/template.yaml" }
  }

  expect_failures = [var.template]
}

run "rejects_http_template_url" {
  command = plan

  variables {
    template = { url = "http://bucket.s3.amazonaws.com/template.yaml" }
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

run "rejects_s3_uri_scheme" {
  command = plan

  variables {
    template = { url = "s3://bucket/template.yaml" }
  }

  expect_failures = [var.template]
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
    parameters = { "Instance-Count" = "3" }
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
    capabilities = ["CAPABILITY_RESOURCE_POLICY"]
  }

  expect_failures = [var.capabilities]
}

run "rejects_lowercase_capability" {
  command = plan

  variables {
    capabilities = ["capability_iam"]
  }

  expect_failures = [var.capabilities]
}

run "rejects_unknown_on_failure" {
  command = plan

  variables {
    on_failure = "RETAIN"
  }

  expect_failures = [var.on_failure]
}

run "accepts_null_on_failure" {
  command = plan

  variables {
    on_failure = null
  }
}

run "rejects_zero_timeout_in_minutes" {
  command = plan

  variables {
    timeout_in_minutes = 0
  }

  expect_failures = [var.timeout_in_minutes]
}

run "rejects_fractional_timeout_in_minutes" {
  command = plan

  variables {
    timeout_in_minutes = 1.5
  }

  expect_failures = [var.timeout_in_minutes]
}

run "rejects_more_than_5_notification_arns" {
  command = plan

  variables {
    notification_arns = [for i in range(6) : "arn:aws:sns:us-east-1:123456789012:topic${i}"]
  }

  expect_failures = [var.notification_arns]
}

run "rejects_non_sns_notification_arn" {
  command = plan

  variables {
    notification_arns = ["arn:aws:sqs:us-east-1:123456789012:queue"]
  }

  expect_failures = [var.notification_arns]
}

run "rejects_stack_policy_with_neither" {
  command = plan

  variables {
    stack_policy = {}
  }

  expect_failures = [var.stack_policy]
}

run "rejects_stack_policy_with_both" {
  command = plan

  variables {
    stack_policy = { body = "{}", url = "https://bucket.s3.amazonaws.com/p.json" }
  }

  expect_failures = [var.stack_policy]
}

run "rejects_non_json_stack_policy_body" {
  command = plan

  variables {
    stack_policy = { body = "Statement: []" }
  }

  expect_failures = [var.stack_policy]
}

run "rejects_stack_policy_body_over_16384_bytes" {
  command = plan

  variables {
    stack_policy = { body = "{\"Statement\":[],\"Pad\":\"${format("%16370s", "")}\"}" }
  }

  expect_failures = [var.stack_policy]
}

run "rejects_non_s3_stack_policy_url" {
  command = plan

  variables {
    stack_policy = { url = "https://example.com/policy.json" }
  }

  expect_failures = [var.stack_policy]
}

run "rejects_non_role_iam_arn" {
  command = plan

  variables {
    iam_role_arn = "arn:aws:iam::123456789012:user/deployer"
  }

  expect_failures = [var.iam_role_arn]
}

run "rejects_bare_role_name" {
  command = plan

  variables {
    iam_role_arn = "vendor-agent-deployer"
  }

  expect_failures = [var.iam_role_arn]
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
    tags = { "aws:cloudformation:stack-name" = "x" }
  }

  expect_failures = [var.tags]
}

run "rejects_malformed_timeout" {
  command = plan

  variables {
    timeouts = { create = "30 minutes" }
  }

  expect_failures = [var.timeouts]
}
