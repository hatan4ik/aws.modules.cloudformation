# Apply-mode contract test, isolated in its own file because run blocks in one
# file share state. The role ARN is computed by IAM, so override_resource
# supplies a realistic one; the second run feeds the output into the root
# module's iam_role_arn unchanged.

mock_provider "aws" {}

variables {
  name       = "cloudformation-artifacts"
  path       = "/cloudformation/"
  account_id = "123456789012"
  statements = {
    SsmParameter = {
      actions   = ["ssm:PutParameter"]
      resources = ["arn:aws:ssm:us-east-1:123456789012:parameter/artifacts/*"]
    }
  }
}

override_resource {
  target = aws_iam_role.this
  values = {
    arn = "arn:aws:iam::123456789012:role/cloudformation/cloudformation-artifacts"
  }
}

run "every_output_resolves" {
  command = apply

  assert {
    condition     = output.role_arn == "arn:aws:iam::123456789012:role/cloudformation/cloudformation-artifacts" && output.role_name == "cloudformation-artifacts"
    error_message = "role_arn and role_name must be the role's."
  }

  assert {
    condition     = keys(output.inline_policies) == ["CloudFormationTemplate"] && jsondecode(output.inline_policies["CloudFormationTemplate"]).Statement[0].Sid == "SsmParameter"
    error_message = "inline_policies must hold the template policy, and no pass-role policy when pass_roles is empty."
  }
}

run "inline_policies_includes_pass_role_when_set" {
  command = apply

  variables {
    pass_roles = {
      FunctionRoles = { role_arns = ["arn:aws:iam::123456789012:role/artifacts-*"], services = ["lambda.amazonaws.com"] }
    }
  }

  assert {
    condition     = keys(output.inline_policies) == ["CloudFormationPassRole", "CloudFormationTemplate"] && jsondecode(output.inline_policies["CloudFormationPassRole"]).Statement[0].Action == "iam:PassRole"
    error_message = "inline_policies must add the pass-role policy, by name, when pass_roles is set."
  }
}

# role_arn passes the root module's iam_role_arn validation, path included,
# and reaches the stack unchanged.
run "plugs_into_the_root_module" {
  command = plan

  module {
    source = "../.."
  }

  variables {
    name         = "artifacts"
    template     = { body = "{\"Resources\":{\"Handle\":{\"Type\":\"AWS::CloudFormation::WaitConditionHandle\"}}}" }
    iam_role_arn = run.every_output_resolves.role_arn
  }

  assert {
    condition     = aws_cloudformation_stack.this.iam_role_arn == "arn:aws:iam::123456789012:role/cloudformation/cloudformation-artifacts"
    error_message = "The root module must accept role_arn as its iam_role_arn and send it."
  }
}
