mock_provider "aws" {}

variables {
  name     = "baseline-config"
  template = { url = "https://baseline-templates.s3.us-east-1.amazonaws.com/config/v3.yaml" }

  permission_model = {
    self_managed = {
      administration_role_arn = "arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"
    }
  }

  stack_instances = {
    "222222222222/us-east-1" = {}
    "222222222222/eu-west-1" = {}
    "333333333333/us-east-1" = { parameter_overrides = { RetentionDays = "30" }, retain_stack = true }
  }
}

run "renders_a_self_managed_stack_set" {
  command = plan

  assert {
    condition     = aws_cloudformation_stack_set.this.name == "baseline-config" && aws_cloudformation_stack_set.this.permission_model == "SELF_MANAGED"
    error_message = "A self_managed branch must render a SELF_MANAGED StackSet named after var.name."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.administration_role_arn == "arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"
    error_message = "The administration role must be sent explicitly."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.execution_role_name == "AWSCloudFormationStackSetExecutionRole"
    error_message = "execution_role_name must default to the AWS standard name and be sent explicitly."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.call_as == null && length(aws_cloudformation_stack_set.this.auto_deployment) == 0
    error_message = "A self-managed StackSet must send neither call_as nor auto_deployment, which are service-managed only."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.template_url == "https://baseline-templates.s3.us-east-1.amazonaws.com/config/v3.yaml"
    error_message = "template.url must pass through as template_url."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.managed_execution[0].active == true
    error_message = "Managed execution must be on by default, so parallel instance operations queue instead of failing."
  }

  assert {
    condition     = length(aws_cloudformation_stack_set.this.operation_preferences) == 0
    error_message = "With no operation_preferences set, no block may be sent, so the safest API defaults (tolerance 0, one account at a time) apply."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.tags == tomap({ Name = "baseline-config" })
    error_message = "The module must add exactly one tag by default: Name = name."
  }
}

run "renders_one_instance_per_account_and_region" {
  command = plan

  assert {
    condition     = toset(keys(aws_cloudformation_stack_set_instance.this)) == toset(["222222222222/us-east-1", "222222222222/eu-west-1", "333333333333/us-east-1"])
    error_message = "There must be exactly one instance per stack_instances key."
  }

  assert {
    condition     = aws_cloudformation_stack_set_instance.this["222222222222/eu-west-1"].account_id == "222222222222" && aws_cloudformation_stack_set_instance.this["222222222222/eu-west-1"].stack_set_instance_region == "eu-west-1"
    error_message = "The account and region must be taken from the instance key."
  }

  assert {
    condition     = alltrue([for instance in aws_cloudformation_stack_set_instance.this : instance.stack_set_name == "baseline-config" && length(instance.deployment_targets) == 0 && instance.call_as == null])
    error_message = "Self-managed instances must target an account directly, without deployment_targets or call_as."
  }

  assert {
    condition     = aws_cloudformation_stack_set_instance.this["333333333333/us-east-1"].parameter_overrides == tomap({ RetentionDays = "30" }) && aws_cloudformation_stack_set_instance.this["333333333333/us-east-1"].retain_stack == true
    error_message = "parameter_overrides and retain_stack must pass through per instance."
  }

  assert {
    condition     = aws_cloudformation_stack_set_instance.this["222222222222/us-east-1"].parameter_overrides == null && aws_cloudformation_stack_set_instance.this["222222222222/us-east-1"].retain_stack == false
    error_message = "An instance without overrides must send none and must not retain its stack by default."
  }

  assert {
    condition     = output.permission_model == "SELF_MANAGED"
    error_message = "permission_model must report SELF_MANAGED."
  }
}

run "passes_a_custom_execution_role_and_inline_template" {
  command = plan

  variables {
    template     = { body = "{\"Resources\":{\"Handle\":{\"Type\":\"AWS::CloudFormation::WaitConditionHandle\"}}}" }
    parameters   = { RetentionDays = "90" }
    capabilities = ["CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"]
    description  = "Baseline AWS Config recorder"
    permission_model = {
      self_managed = {
        administration_role_arn = "arn:aws:iam::111111111111:role/stacksets/baseline-admin"
        execution_role_name     = "baseline-stackset-execution"
      }
    }
    managed_execution_active = false
    tags                     = { Name = "caller-chosen", Owner = "security" }
    timeouts                 = { stack_set_update = "3h", instance_create = "1h", instance_update = "1h", instance_delete = "45m" }
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.execution_role_name == "baseline-stackset-execution" && aws_cloudformation_stack_set.this.template_url == null
    error_message = "A custom execution role must pass through, and an inline template must not send a URL."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.parameters == tomap({ RetentionDays = "90" }) && aws_cloudformation_stack_set.this.capabilities == toset(["CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"]) && aws_cloudformation_stack_set.this.description == "Baseline AWS Config recorder"
    error_message = "parameters, capabilities (CAPABILITY_AUTO_EXPAND is allowed for self_managed), and description must pass through."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.managed_execution[0].active == false
    error_message = "managed_execution_active = false must be honoured."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.tags == tomap({ Name = "caller-chosen", Owner = "security" })
    error_message = "A caller's Name tag must override the module's Name = name default."
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.timeouts.update == "3h" && aws_cloudformation_stack_set_instance.this["222222222222/us-east-1"].timeouts.create == "1h" && aws_cloudformation_stack_set_instance.this["222222222222/us-east-1"].timeouts.update == "1h" && aws_cloudformation_stack_set_instance.this["222222222222/us-east-1"].timeouts.delete == "45m"
    error_message = "Timeouts must reach the StackSet (update) and every instance (create, update, delete)."
  }
}
