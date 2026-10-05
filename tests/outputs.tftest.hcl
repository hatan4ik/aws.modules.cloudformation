# Apply-mode contract test, isolated in its own file because run blocks in one
# file share state and an apply would leak into later plan runs. The stack ID
# and its Outputs are computed by CloudFormation, so they are unknown under
# command = plan; override_resource gives them realistic values so every
# module output is proven to resolve from the right attribute.

mock_provider "aws" {}

variables {
  name         = "vendor-agent"
  template     = { url = "https://vendor-templates.s3.us-east-1.amazonaws.com/agent.yaml" }
  iam_role_arn = "arn:aws:iam::123456789012:role/vendor-agent-deployer"
}

override_resource {
  target = aws_cloudformation_stack.this
  values = {
    id = "arn:aws:cloudformation:us-east-1:123456789012:stack/vendor-agent/0c6b1f80-a1b2-11ef-8f3c-0a1b2c3d4e5f"
    outputs = {
      AgentRoleArn = "arn:aws:iam::123456789012:role/vendor-agent"
      QueueUrl     = "https://sqs.us-east-1.amazonaws.com/123456789012/vendor-agent"
    }
  }
}

run "every_output_resolves" {
  command = apply

  assert {
    condition     = output.id == "arn:aws:cloudformation:us-east-1:123456789012:stack/vendor-agent/0c6b1f80-a1b2-11ef-8f3c-0a1b2c3d4e5f"
    error_message = "id must be the stack ID CloudFormation assigned."
  }

  assert {
    condition     = output.arn == output.id && can(regex("^arn:aws:cloudformation:[a-z0-9-]+:[0-9]{12}:stack/vendor-agent/[0-9a-f-]+$", output.arn))
    error_message = "arn must be the stack ARN, which CloudFormation returns as the stack ID."
  }

  assert {
    condition     = output.name == "vendor-agent"
    error_message = "name must be the stack name."
  }

  assert {
    condition     = output.outputs == tomap({ AgentRoleArn = "arn:aws:iam::123456789012:role/vendor-agent", QueueUrl = "https://sqs.us-east-1.amazonaws.com/123456789012/vendor-agent" })
    error_message = "outputs must expose the stack's CloudFormation Outputs map unchanged."
  }
}
