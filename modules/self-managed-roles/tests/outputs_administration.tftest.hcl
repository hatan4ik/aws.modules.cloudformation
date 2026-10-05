# Apply-mode contract test for an administration call, isolated in its own
# file because run blocks in one file share state. The role ARN is computed by
# IAM, so override_resource supplies a realistic one and every output is
# proven to resolve from the right attribute.

mock_provider "aws" {}

variables {
  role = {
    administration = {
      account_id          = "111111111111"
      execution_role_name = "baseline-stackset-execution"
    }
  }
}

override_resource {
  target = aws_iam_role.administration
  values = {
    arn = "arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"
  }
}

run "every_output_resolves" {
  command = apply

  assert {
    condition     = output.role_arn == "arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole" && output.role_name == "AWSCloudFormationStackSetAdministrationRole"
    error_message = "role_arn and role_name must be the administration role's."
  }

  assert {
    condition = output.stack_set_permission_model == {
      self_managed = {
        administration_role_arn = "arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"
        execution_role_name     = "baseline-stackset-execution"
      }
    }
    error_message = "stack_set_permission_model must carry the role ARN and the execution role name the role's policy allows, in modules/stack-set's permission_model shape."
  }
}

# The output plugs into modules/stack-set unchanged: the StackSet receives the
# role ARN and execution role name exactly as this module produced them.
run "plugs_into_the_stack_set_module" {
  command = plan

  module {
    source = "../stack-set"
  }

  variables {
    name             = "baseline-config"
    template         = { body = "{\"Resources\":{\"Handle\":{\"Type\":\"AWS::CloudFormation::WaitConditionHandle\"}}}" }
    permission_model = run.every_output_resolves.stack_set_permission_model
    stack_instances  = { "222222222222/us-east-1" = {} }
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.permission_model == "SELF_MANAGED" && aws_cloudformation_stack_set.this.administration_role_arn == "arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole" && aws_cloudformation_stack_set.this.execution_role_name == "baseline-stackset-execution"
    error_message = "modules/stack-set must accept stack_set_permission_model as its permission_model and send both values."
  }
}
