# Apply-mode contract test for a self-managed StackSet, isolated in its own
# file because run blocks in one file share state and an apply would leak into
# later plan runs. IDs, ARNs, and instance stack IDs are computed by
# CloudFormation, so override_resource supplies realistic values and every
# output is proven to resolve from the right attribute.

mock_provider "aws" {}

variables {
  name     = "baseline-config"
  template = { url = "https://baseline-templates.s3.amazonaws.com/config.yaml" }

  permission_model = {
    self_managed = {
      administration_role_arn = "arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"
    }
  }

  stack_instances = {
    "222222222222/us-east-1" = {}
    "333333333333/eu-west-1" = {}
  }
}

override_resource {
  target = aws_cloudformation_stack_set.this
  values = {
    stack_set_id = "baseline-config:7d1f4c6e-0a1b-4c2d-9e8f-0123456789ab"
    arn          = "arn:aws:cloudformation:us-east-1:111111111111:stackset/baseline-config:7d1f4c6e-0a1b-4c2d-9e8f-0123456789ab"
  }
}

override_resource {
  target = aws_cloudformation_stack_set_instance.this["222222222222/us-east-1"]
  values = {
    id       = "baseline-config,222222222222,us-east-1"
    stack_id = "arn:aws:cloudformation:us-east-1:222222222222:stack/StackSet-baseline-config-1111/aaaaaaaa-0000-0000-0000-000000000001"
  }
}

override_resource {
  target = aws_cloudformation_stack_set_instance.this["333333333333/eu-west-1"]
  values = {
    id       = "baseline-config,333333333333,eu-west-1"
    stack_id = "arn:aws:cloudformation:eu-west-1:333333333333:stack/StackSet-baseline-config-2222/aaaaaaaa-0000-0000-0000-000000000002"
  }
}

run "every_output_resolves" {
  command = apply

  assert {
    condition     = output.id == "baseline-config:7d1f4c6e-0a1b-4c2d-9e8f-0123456789ab"
    error_message = "id must be the StackSet ID CloudFormation assigned."
  }

  assert {
    condition     = output.arn == "arn:aws:cloudformation:us-east-1:111111111111:stackset/baseline-config:7d1f4c6e-0a1b-4c2d-9e8f-0123456789ab"
    error_message = "arn must be the StackSet ARN."
  }

  assert {
    condition     = output.name == "baseline-config" && output.permission_model == "SELF_MANAGED"
    error_message = "name and permission_model must resolve."
  }

  assert {
    condition     = toset(keys(output.stack_instances)) == toset(["222222222222/us-east-1", "333333333333/eu-west-1"])
    error_message = "stack_instances must be keyed exactly like the input."
  }

  assert {
    condition = alltrue([
      output.stack_instances["333333333333/eu-west-1"].id == "baseline-config,333333333333,eu-west-1",
      output.stack_instances["333333333333/eu-west-1"].region == "eu-west-1",
      output.stack_instances["333333333333/eu-west-1"].organizational_unit_id == null,
      output.stack_instances["333333333333/eu-west-1"].account_ids == tolist(["333333333333"]),
      output.stack_instances["333333333333/eu-west-1"].stack_ids == tolist(["arn:aws:cloudformation:eu-west-1:333333333333:stack/StackSet-baseline-config-2222/aaaaaaaa-0000-0000-0000-000000000002"]),
    ])
    error_message = "A self-managed instance must report its own ID, region, its one account, and its one stack ID, with no OU."
  }
}
