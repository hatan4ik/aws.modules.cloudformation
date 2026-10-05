# Apply-mode contract test for a service-managed StackSet; see
# outputs_self_managed.tftest.hcl for why it is isolated. An OU-targeted
# instance reaches every account in the OU, which the provider reports in
# stack_instance_summaries rather than in account_id and stack_id.

mock_provider "aws" {}

variables {
  name     = "org-guardduty-baseline"
  template = { url = "https://baseline-templates.s3.amazonaws.com/guardduty.yaml?versionId=Kq2c8eTP" }

  permission_model = {
    service_managed = {
      auto_deployment = { enabled = true }
    }
  }

  stack_instances = {
    "ou-ab12-11111111/us-east-1" = {}
  }
}

override_resource {
  target = aws_cloudformation_stack_set.this
  values = {
    stack_set_id = "org-guardduty-baseline:11111111-2222-3333-4444-555555555555"
    arn          = "arn:aws:cloudformation:us-east-1:111111111111:stackset/org-guardduty-baseline:11111111-2222-3333-4444-555555555555"
  }
}

override_resource {
  target = aws_cloudformation_stack_set_instance.this
  values = {
    id = "org-guardduty-baseline,ou-ab12-11111111,us-east-1"
    stack_instance_summaries = [
      {
        account_id             = "222222222222"
        organizational_unit_id = "ou-ab12-11111111"
        stack_id               = "arn:aws:cloudformation:us-east-1:222222222222:stack/StackSet-org-guardduty-baseline-1/aaaaaaaa-0000-0000-0000-000000000001"
      },
      {
        account_id             = "333333333333"
        organizational_unit_id = "ou-ab12-11111111"
        stack_id               = "arn:aws:cloudformation:us-east-1:333333333333:stack/StackSet-org-guardduty-baseline-2/aaaaaaaa-0000-0000-0000-000000000002"
      },
    ]
  }
}

run "every_output_resolves" {
  command = apply

  assert {
    condition     = output.id == "org-guardduty-baseline:11111111-2222-3333-4444-555555555555" && output.permission_model == "SERVICE_MANAGED"
    error_message = "id and permission_model must resolve."
  }

  assert {
    condition = alltrue([
      output.stack_instances["ou-ab12-11111111/us-east-1"].id == "org-guardduty-baseline,ou-ab12-11111111,us-east-1",
      output.stack_instances["ou-ab12-11111111/us-east-1"].region == "us-east-1",
      output.stack_instances["ou-ab12-11111111/us-east-1"].organizational_unit_id == "ou-ab12-11111111",
      output.stack_instances["ou-ab12-11111111/us-east-1"].account_ids == tolist(["222222222222", "333333333333"]),
      output.stack_instances["ou-ab12-11111111/us-east-1"].stack_ids == tolist([
        "arn:aws:cloudformation:us-east-1:222222222222:stack/StackSet-org-guardduty-baseline-1/aaaaaaaa-0000-0000-0000-000000000001",
        "arn:aws:cloudformation:us-east-1:333333333333:stack/StackSet-org-guardduty-baseline-2/aaaaaaaa-0000-0000-0000-000000000002",
      ]),
    ])
    error_message = "An OU instance must report its OU and every account and stack the deployment reached."
  }
}
