provider "aws" {
  region = var.region
}

module "vendor_agent" {
  source = "../../"

  name = var.name

  # The template ships with the configuration, so a template change is a
  # reviewed diff in the same pull request as everything else.
  template = { body = file("${path.module}/vendor-agent.yaml") }

  # Declare every parameter you rely on, including ones with a template
  # Default, so the plan shows exactly what the stack runs with.
  parameters = {
    AgentName       = var.name
    RetentionInDays = "90"
  }

  # A least-privilege role CloudFormation assumes for every operation on this
  # stack, instead of the credentials of whoever runs Terraform.
  iam_role_arn = var.cloudformation_role_arn

  # Stack events (including a failed create) go to a topic someone watches.
  notification_arns = [var.notification_topic_arn]

  # Nothing in the stack may be replaced or deleted by a stack update; the
  # vendor's next template version must go through a policy change first.
  stack_policy = {
    body = jsonencode({
      Statement = [
        { Effect = "Allow", Action = "Update:Modify", Principal = "*", Resource = "*" },
        { Effect = "Deny", Action = ["Update:Replace", "Update:Delete"], Principal = "*", Resource = "*" },
      ]
    })
  }

  tags = {
    Environment = "example"
    Owner       = "platform"
  }
}

# The stack's own Outputs are how the rest of the configuration composes
# around it.
resource "aws_cloudwatch_log_subscription_filter" "forward" {
  count = var.destination_arn == null ? 0 : 1

  name            = "${var.name}-forward"
  log_group_name  = module.vendor_agent.outputs["LogGroupName"]
  filter_pattern  = ""
  destination_arn = var.destination_arn
}
