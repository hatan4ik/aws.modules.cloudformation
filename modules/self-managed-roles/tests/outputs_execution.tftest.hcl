# Apply-mode contract test for an execution call, isolated in its own file.

mock_provider "aws" {}

variables {
  role = {
    execution = {
      administration_role_arns = ["arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"]
    }
  }
}

override_resource {
  target = aws_iam_role.execution
  values = {
    arn = "arn:aws:iam::222222222222:role/AWSCloudFormationStackSetExecutionRole"
  }
}

run "every_output_resolves" {
  command = apply

  assert {
    condition     = output.role_arn == "arn:aws:iam::222222222222:role/AWSCloudFormationStackSetExecutionRole" && output.role_name == "AWSCloudFormationStackSetExecutionRole"
    error_message = "role_arn and role_name must be the execution role's."
  }

  assert {
    condition     = output.stack_set_permission_model == null
    error_message = "An execution call has no StackSet permission model to offer."
  }
}
