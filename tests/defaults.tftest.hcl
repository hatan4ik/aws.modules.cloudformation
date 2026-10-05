mock_provider "aws" {}

variables {
  name = "vendor-agent"
  template = {
    body = <<-YAML
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        Handle:
          Type: AWS::CloudFormation::WaitConditionHandle
    YAML
  }
  # A service role keeps the advisory check quiet in every run but the first,
  # which proves the bare defaults.
  iam_role_arn = "arn:aws:iam::123456789012:role/vendor-agent-deployer"
}

run "renders_a_minimal_stack_with_api_defaults" {
  command = plan

  variables {
    iam_role_arn = null
  }

  # Without a service role the advisory check warns; it must not block.
  expect_failures = [check.service_role_not_set]

  assert {
    condition     = aws_cloudformation_stack.this.name == "vendor-agent"
    error_message = "The stack must be named after var.name."
  }

  assert {
    condition     = aws_cloudformation_stack.this.template_url == null
    error_message = "An inline template must not also send a template URL."
  }

  assert {
    condition     = aws_cloudformation_stack.this.on_failure == null
    error_message = "on_failure must not be sent by default: CloudFormation then applies its own default, ROLLBACK, and an imported stack (on_failure null in state) plans no change."
  }

  assert {
    condition     = aws_cloudformation_stack.this.timeout_in_minutes == null
    error_message = "No CloudFormation-side creation timeout may be set by default."
  }

  assert {
    condition     = aws_cloudformation_stack.this.capabilities == null || length(coalesce(aws_cloudformation_stack.this.capabilities, [])) == 0
    error_message = "No capability may be acknowledged by default."
  }

  assert {
    condition     = aws_cloudformation_stack.this.iam_role_arn == null && aws_cloudformation_stack.this.policy_url == null
    error_message = "No service role or stack policy URL may be set by default."
  }

  assert {
    condition     = aws_cloudformation_stack.this.tags == tomap({ Name = "vendor-agent" })
    error_message = "The module must add exactly one tag by default: Name = name."
  }
}

run "renders_every_optional_input" {
  command = plan

  variables {
    template           = { url = "https://vendor-templates.s3.us-east-1.amazonaws.com/agent/v4.2/agent.yaml" }
    parameters         = { InstanceCount = "3", Subnets = "subnet-0123456789abcdef0,subnet-0fedcba9876543210" }
    capabilities       = ["CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"]
    on_failure         = "DELETE"
    timeout_in_minutes = 60
    notification_arns  = ["arn:aws:sns:us-east-1:123456789012:stack-events"]
    stack_policy       = { body = "{\"Statement\":[{\"Effect\":\"Deny\",\"Action\":\"Update:Replace\",\"Principal\":\"*\",\"Resource\":\"*\"}]}" }
    iam_role_arn       = "arn:aws:iam::123456789012:role/cfn/vendor-agent-deployer"
    timeouts           = { create = "1h30m", update = "45m", delete = "20m" }
  }

  assert {
    condition     = aws_cloudformation_stack.this.template_url == "https://vendor-templates.s3.us-east-1.amazonaws.com/agent/v4.2/agent.yaml"
    error_message = "template.url must pass through as template_url."
  }

  assert {
    condition     = aws_cloudformation_stack.this.parameters == tomap({ InstanceCount = "3", Subnets = "subnet-0123456789abcdef0,subnet-0fedcba9876543210" })
    error_message = "parameters must pass through unchanged, as strings."
  }

  assert {
    condition     = aws_cloudformation_stack.this.capabilities == toset(["CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"])
    error_message = "capabilities must pass through unchanged."
  }

  assert {
    condition     = aws_cloudformation_stack.this.on_failure == "DELETE" && aws_cloudformation_stack.this.timeout_in_minutes == 60
    error_message = "on_failure and timeout_in_minutes must pass through."
  }

  assert {
    condition     = aws_cloudformation_stack.this.notification_arns == toset(["arn:aws:sns:us-east-1:123456789012:stack-events"])
    error_message = "notification_arns must pass through."
  }

  assert {
    condition     = aws_cloudformation_stack.this.policy_url == null && aws_cloudformation_stack.this.policy_body != null
    error_message = "A stack policy body must be sent as policy_body only."
  }

  assert {
    condition     = aws_cloudformation_stack.this.iam_role_arn == "arn:aws:iam::123456789012:role/cfn/vendor-agent-deployer"
    error_message = "iam_role_arn must pass through."
  }

  assert {
    condition     = aws_cloudformation_stack.this.timeouts.create == "1h30m" && aws_cloudformation_stack.this.timeouts.update == "45m" && aws_cloudformation_stack.this.timeouts.delete == "20m"
    error_message = "Terraform-side timeouts must pass through."
  }
}

run "sends_a_stack_policy_url_alone" {
  command = plan

  variables {
    stack_policy = { url = "https://s3.amazonaws.com/policies-bucket/stack-policy.json" }
  }

  assert {
    condition     = aws_cloudformation_stack.this.policy_url == "https://s3.amazonaws.com/policies-bucket/stack-policy.json"
    error_message = "A stack policy URL must be sent as policy_url."
  }
}

run "caller_tags_win_over_the_module_name_tag" {
  command = plan

  variables {
    tags = { Name = "caller-chosen", Owner = "platform" }
  }

  assert {
    condition     = aws_cloudformation_stack.this.tags == tomap({ Name = "caller-chosen", Owner = "platform" })
    error_message = "A caller's Name tag must override the module's Name = name default (merge({ Name = name }, tags))."
  }
}

run "adds_name_beside_caller_tags" {
  command = plan

  variables {
    tags = { Environment = "prod" }
  }

  assert {
    condition     = aws_cloudformation_stack.this.tags == tomap({ Name = "vendor-agent", Environment = "prod" })
    error_message = "Caller tags must be kept and Name added beside them."
  }
}

run "accepts_boundary_values" {
  command = plan

  variables {
    name               = "a"
    timeout_in_minutes = 1
    parameters         = { for i in range(200) : "P${i}" => "v" }
    tags               = { for i in range(49) : "k${i}" => "v" }
  }

  assert {
    condition     = length(aws_cloudformation_stack.this.parameters) == 200 && length(aws_cloudformation_stack.this.tags) == 50
    error_message = "200 parameters and 50 tags including Name are the documented maximums and must be accepted."
  }
}

run "accepts_a_template_of_exactly_51200_bytes" {
  command = plan

  variables {
    # 51,200 bytes: a JSON string padded to the limit, with a multi-byte
    # character so the byte count, not the character count, is what is checked.
    # 18 bytes of prefix ("é" is 2 bytes), 51,180 of padding, 2 of suffix.
    template = { body = "{\"Description\":\"é${format("%51180s", "")}\"}" }
  }

  assert {
    condition     = aws_cloudformation_stack.this.template_url == null
    error_message = "A body at exactly the 51,200-byte limit must be accepted."
  }
}
