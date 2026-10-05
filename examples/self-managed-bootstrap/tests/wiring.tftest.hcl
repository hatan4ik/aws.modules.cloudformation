# Credential-free proof that the example wires the three calls together and
# applies end to end against mocked providers: the administration role in the
# administrator account, the execution role in the target account, and a
# StackSet whose permission model names both. The policy documents themselves
# are asserted in modules/self-managed-roles/tests. Role ARNs are computed by
# IAM, so override_resource supplies realistic ones.

mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.administrator
    values = { account_id = "111111111111" }
  }

  override_data {
    target = data.aws_partition.current
    values = { partition = "aws" }
  }
}

mock_provider "aws" {
  alias = "target"
}

variables {
  target_account_id       = "222222222222"
  target_account_role_arn = "arn:aws:iam::222222222222:role/OrganizationAccountAccessRole"
}

override_resource {
  target = module.stack_set_administration_role.aws_iam_role.administration
  values = { arn = "arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole" }
}

override_resource {
  target = module.stack_set_execution_role.aws_iam_role.execution
  values = { arn = "arn:aws:iam::222222222222:role/AWSCloudFormationStackSetExecutionRole" }
}

run "bootstraps_a_self_managed_stack_set_from_zero" {
  command = apply

  assert {
    condition     = output.administration_role_arn == "arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole" && output.execution_role_arn == "arn:aws:iam::222222222222:role/AWSCloudFormationStackSetExecutionRole"
    error_message = "Both roles must be created."
  }

  assert {
    condition     = module.stack_set_administration_role.stack_set_permission_model.self_managed.administration_role_arn == output.administration_role_arn && module.stack_set_administration_role.stack_set_permission_model.self_managed.execution_role_name == module.stack_set_execution_role.role_name
    error_message = "The StackSet's permission model must name the administration role created here and the execution role created in the target account."
  }

  assert {
    condition = alltrue([
      module.parameter_baseline.permission_model == "SELF_MANAGED",
      module.parameter_baseline.stack_instances["222222222222/us-east-1"].account_ids == tolist(["222222222222"]),
    ])
    error_message = "The StackSet must be self-managed and deploy one instance to the target account."
  }
}
