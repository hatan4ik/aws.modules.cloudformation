mock_provider "aws" {}

variables {
  name     = "vendor-agent"
  template = { url = "https://vendor-templates.s3.amazonaws.com/agent.yaml" }
}

run "warns_without_a_service_role" {
  command = plan

  expect_failures = [check.service_role_not_set]
}

run "is_silent_with_a_service_role" {
  command = plan

  variables {
    iam_role_arn = "arn:aws:iam::123456789012:role/vendor-agent-deployer"
  }

  assert {
    condition     = aws_cloudformation_stack.this.iam_role_arn == "arn:aws:iam::123456789012:role/vendor-agent-deployer"
    error_message = "The service role must be used and service_role_not_set must not fire."
  }
}
