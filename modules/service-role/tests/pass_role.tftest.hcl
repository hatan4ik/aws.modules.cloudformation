# iam:PassRole grants for templates that hand a role to a service.

mock_provider "aws" {}

variables {
  name       = "cloudformation-functions"
  account_id = "123456789012"
  statements = {
    LambdaFunction = {
      actions   = ["lambda:CreateFunction", "lambda:DeleteFunction", "lambda:GetFunction"]
      resources = ["arn:aws:lambda:us-east-1:123456789012:function:functions-*"]
    }
  }
}

run "renders_scoped_pass_role_grants" {
  command = plan

  variables {
    pass_roles = {
      FunctionRoles = {
        role_arns = ["arn:aws:iam::123456789012:role/functions-*"]
        services  = ["lambda.amazonaws.com"]
      }
      SchedulerRole = {
        role_arns = ["arn:aws:iam::123456789012:role/scheduler/invoke", "arn:aws:iam::123456789012:role/scheduler/dlq"]
        services  = ["scheduler.amazonaws.com", "events.amazonaws.com"]
      }
    }
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.pass_role[0].policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "FunctionRoles"
          Effect    = "Allow"
          Action    = "iam:PassRole"
          Resource  = ["arn:aws:iam::123456789012:role/functions-*"]
          Condition = { StringEquals = { "iam:PassedToService" = ["lambda.amazonaws.com"] } }
        },
        {
          Sid       = "SchedulerRole"
          Effect    = "Allow"
          Action    = "iam:PassRole"
          Resource  = ["arn:aws:iam::123456789012:role/scheduler/dlq", "arn:aws:iam::123456789012:role/scheduler/invoke"]
          Condition = { StringEquals = { "iam:PassedToService" = ["events.amazonaws.com", "scheduler.amazonaws.com"] } }
        },
      ]
    }
    error_message = "Each grant must be iam:PassRole on exactly its roles, only to its services (iam:PassedToService), in Sid order."
  }

  assert {
    condition     = aws_iam_role_policy.pass_role[0].name == "CloudFormationPassRole" && !strcontains(aws_iam_role_policy.template.policy, "iam:PassRole")
    error_message = "Pass-role grants must be their own policy, never mixed into the template policy."
  }
}
