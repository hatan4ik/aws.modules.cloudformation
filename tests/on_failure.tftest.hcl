# on_failure is create-only and never read back by the provider, so the stack
# ignores changes to it. These runs pin that contract: an edit on an existing
# stack is a no-op instead of a replacement. The import case (on_failure null
# in state, any value in config) is the same mechanism; see docs/DESIGN.md D11
# for the real-provider plan evidence.

mock_provider "aws" {}

variables {
  name         = "vendor-agent"
  template     = { body = "{\"Resources\":{\"Handle\":{\"Type\":\"AWS::CloudFormation::WaitConditionHandle\"}}}" }
  iam_role_arn = "arn:aws:iam::123456789012:role/vendor-agent-deployer"
}

run "creates_with_the_configured_on_failure" {
  variables {
    on_failure = "DELETE"
  }

  assert {
    condition     = aws_cloudformation_stack.this.on_failure == "DELETE"
    error_message = "A set on_failure must be sent on create."
  }
}

run "changing_on_failure_later_does_not_replace_the_stack" {
  command = plan

  variables {
    on_failure = "DO_NOTHING"
  }

  assert {
    condition     = aws_cloudformation_stack.this.on_failure == "DELETE"
    error_message = "on_failure must be ignored on an existing stack: the plan keeps the created value instead of forcing a replacement."
  }
}

run "unsetting_on_failure_later_does_not_replace_the_stack" {
  command = plan

  variables {
    on_failure = null
  }

  assert {
    condition     = aws_cloudformation_stack.this.on_failure == "DELETE"
    error_message = "Moving to the null default must not replace a stack created with an explicit on_failure (the v1.0.0 upgrade path)."
  }
}
