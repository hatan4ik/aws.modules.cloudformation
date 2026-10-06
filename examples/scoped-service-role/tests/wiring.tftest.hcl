# Credential-free proof that the example composes modules/service-role with
# the root module end to end, and that the role is scoped to exactly what
# artifacts.yaml creates: two resource types, two resources, no wildcard
# resource, no other service. The role ARN and the stack's ID and Outputs are
# computed by AWS, so override_resource supplies realistic ones.

mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "123456789012" }
  }

  override_data {
    target = data.aws_partition.current
    values = { partition = "aws" }
  }
}

variables {
  notification_topic_arn = "arn:aws:sns:us-east-1:123456789012:stack-events"
}

override_resource {
  target = module.cloudformation_role.aws_iam_role.this
  values = {
    arn = "arn:aws:iam::123456789012:role/cloudformation/cloudformation-scoped-service-role"
  }
}

override_resource {
  target = module.artifacts.aws_cloudformation_stack.this
  values = {
    id      = "arn:aws:cloudformation:us-east-1:123456789012:stack/scoped-service-role/5f0a1c20-a1b2-11f0-9c3d-0a1b2c3d4e5f"
    outputs = { BucketName = "scoped-service-role-123456789012-us-east-1", ParameterName = "/scoped-service-role/bucket-name" }
  }
}

run "applies_a_stack_with_a_scoped_service_role" {
  command = apply

  assert {
    condition     = output.role_arn == "arn:aws:iam::123456789012:role/cloudformation/cloudformation-scoped-service-role" && module.cloudformation_role.role_name == "cloudformation-scoped-service-role"
    error_message = "The service role must be created under /cloudformation/. (That the root module sends role_arn as the stack's iam_role_arn is proven in modules/service-role/tests/outputs.tftest.hcl.)"
  }

  assert {
    condition     = output.bucket_name == "scoped-service-role-123456789012-us-east-1" && startswith(output.stack_id, "arn:aws:cloudformation:")
    error_message = "The example's outputs must resolve from the stack."
  }

  # The template's resource types, read from the file, are exactly the two
  # the statements cover, so the role cannot silently fall behind the template.
  assert {
    condition     = toset(flatten(regexall("(?m)^    Type: (AWS::[A-Za-z0-9:]+)$", file("${path.module}/artifacts.yaml")))) == toset(["AWS::S3::Bucket", "AWS::SSM::Parameter"])
    error_message = "artifacts.yaml must declare exactly an AWS::S3::Bucket and an AWS::SSM::Parameter; update the role's statements with the template."
  }

  assert {
    condition = toset(flatten([
      for statement in jsondecode(module.cloudformation_role.inline_policies["CloudFormationTemplate"]).Statement : [for action in statement.Action : split(":", action)[0]]
    ])) == toset(["s3", "ssm"])
    error_message = "The role must grant actions of S3 and SSM only, the services of the template's two resource types."
  }

  assert {
    condition = toset(flatten([
      for statement in jsondecode(module.cloudformation_role.inline_policies["CloudFormationTemplate"]).Statement : statement.Resource
    ])) == toset(["arn:aws:s3:::scoped-service-role-123456789012-us-east-1", "arn:aws:ssm:us-east-1:123456789012:parameter/scoped-service-role/*"])
    error_message = "The role must be scoped to the bucket and parameter path artifacts.yaml creates, and nothing else (no \"*\" resource)."
  }

  assert {
    condition     = alltrue([for statement in jsondecode(module.cloudformation_role.inline_policies["CloudFormationTemplate"]).Statement : statement.Effect == "Allow" && !contains(statement.Action, "*") && !anytrue([for action in statement.Action : endswith(action, ":*")])])
    error_message = "No statement may grant every action or every action of a service."
  }

  assert {
    condition     = keys(module.cloudformation_role.inline_policies) == ["CloudFormationTemplate"]
    error_message = "artifacts.yaml passes no role, so the service role must have no iam:PassRole."
  }
}
