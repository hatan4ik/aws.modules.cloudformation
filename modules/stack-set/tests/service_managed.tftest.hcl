mock_provider "aws" {}

variables {
  name = "org-guardduty-baseline"
  template = {
    body = <<-YAML
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        Handle:
          Type: AWS::CloudFormation::WaitConditionHandle
    YAML
  }

  permission_model = {
    service_managed = {
      auto_deployment = { enabled = true }
    }
  }

  stack_instances = {
    "ou-ab12-11111111/us-east-1" = {}
    "ou-ab12-11111111/eu-west-1" = {}
    "r-ab12/us-west-2"           = { parameter_overrides = { Mode = "audit" } }
  }
}

run "renders_a_service_managed_stack_set" {
  command = plan

  assert {
    condition     = aws_cloudformation_stack_set.this.permission_model == "SERVICE_MANAGED"
    error_message = "A service_managed branch must render a SERVICE_MANAGED StackSet."
  }

  assert {
    # execution_role_name is optional and computed in the provider, so it plans
    # as unknown here even though the module passes null; the service_managed
    # branch of the type has no such field to pass.
    condition     = aws_cloudformation_stack_set.this.administration_role_arn == null
    error_message = "A service-managed StackSet must not send administration_role_arn."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.auto_deployment[0].enabled == true && aws_cloudformation_stack_set.this.auto_deployment[0].retain_stacks_on_account_removal == false
    error_message = "auto_deployment must be sent, and stacks must not be retained on account removal by default."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.call_as == "SELF"
    error_message = "call_as must default to SELF for a service-managed StackSet."
  }
}

run "targets_ous_and_the_root_through_deployment_targets" {
  command = plan

  assert {
    condition     = length(aws_cloudformation_stack_set_instance.this) == 3
    error_message = "There must be exactly one instance per stack_instances key."
  }

  assert {
    condition     = aws_cloudformation_stack_set_instance.this["ou-ab12-11111111/eu-west-1"].deployment_targets[0].organizational_unit_ids == toset(["ou-ab12-11111111"]) && aws_cloudformation_stack_set_instance.this["ou-ab12-11111111/eu-west-1"].stack_set_instance_region == "eu-west-1"
    error_message = "An OU instance must deploy to the OU from its key, in the region from its key."
  }

  assert {
    condition     = aws_cloudformation_stack_set_instance.this["r-ab12/us-west-2"].deployment_targets[0].organizational_unit_ids == toset(["r-ab12"]) && aws_cloudformation_stack_set_instance.this["r-ab12/us-west-2"].parameter_overrides == tomap({ Mode = "audit" })
    error_message = "A root-ID instance must deploy to the whole organization, with its parameter overrides."
  }

  assert {
    condition     = alltrue([for instance in aws_cloudformation_stack_set_instance.this : instance.call_as == "SELF"])
    error_message = "Every instance must carry the StackSet's call_as."
  }

  assert {
    condition     = output.permission_model == "SERVICE_MANAGED"
    error_message = "permission_model must report SERVICE_MANAGED."
  }
}

run "acts_as_delegated_admin_and_retains_on_removal" {
  command = plan

  variables {
    permission_model = {
      service_managed = {
        auto_deployment = { enabled = true, retain_stacks_on_account_removal = true }
        call_as         = "DELEGATED_ADMIN"
      }
    }
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.call_as == "DELEGATED_ADMIN" && alltrue([for instance in aws_cloudformation_stack_set_instance.this : instance.call_as == "DELEGATED_ADMIN"])
    error_message = "DELEGATED_ADMIN must reach the StackSet and every instance."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.auto_deployment[0].retain_stacks_on_account_removal == true
    error_message = "retain_stacks_on_account_removal must pass through."
  }
}

run "disables_auto_deployment" {
  command = plan

  variables {
    permission_model = {
      service_managed = {
        auto_deployment = { enabled = false }
      }
    }
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.auto_deployment[0].enabled == false
    error_message = "auto_deployment.enabled = false must be sent explicitly."
  }
}
