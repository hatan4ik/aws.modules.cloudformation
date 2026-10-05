# The template advisory checks: template_url_not_version_pinned,
# stack_policy_url_not_version_pinned (docs/DESIGN.md D14), and
# template_body_not_a_mapping (D16). Each warns without blocking; every run
# below sets a service role so service_role_not_set stays quiet and a run
# that expects no failure proves the template checks are silent too.

mock_provider "aws" {}

variables {
  name         = "vendor-agent"
  template     = { url = "https://vendor-templates.s3.us-east-1.amazonaws.com/agent/agent.yaml?versionId=3HL4kqtJlcpXroDTDmJ.rmSpXd3dIbrHY" }
  iam_role_arn = "arn:aws:iam::123456789012:role/vendor-agent-deployer"
}

# --- template.url -----------------------------------------------------------

run "is_silent_for_a_version_pinned_s3_url" {
  command = plan

  assert {
    condition     = aws_cloudformation_stack.this.template_url == "https://vendor-templates.s3.us-east-1.amazonaws.com/agent/agent.yaml?versionId=3HL4kqtJlcpXroDTDmJ.rmSpXd3dIbrHY"
    error_message = "A version-pinned URL must be sent unchanged, query string included."
  }

  assert {
    condition     = !local.template_url_unpinned
    error_message = "A URL with ?versionId= must not be reported as unpinned."
  }
}

run "is_silent_when_version_id_follows_another_query_parameter" {
  command = plan

  variables {
    template = { url = "https://s3.us-east-1.amazonaws.com/vendor-templates/agent.yaml?x-id=GetObject&versionId=3HL4kqtJ" }
  }

  assert {
    condition     = !local.template_url_unpinned
    error_message = "versionId must be found as any query parameter, not only the first."
  }
}

run "warns_for_an_unpinned_virtual_hosted_url" {
  command = plan

  variables {
    template = { url = "https://vendor-templates.s3.us-east-1.amazonaws.com/agent/agent.yaml" }
  }

  expect_failures = [check.template_url_not_version_pinned]
}

run "warns_for_an_unpinned_legacy_global_url" {
  command = plan

  variables {
    template = { url = "https://vendor-templates.s3.amazonaws.com/agent.yaml" }
  }

  expect_failures = [check.template_url_not_version_pinned]
}

run "warns_for_an_unpinned_path_style_url" {
  command = plan

  variables {
    template = { url = "https://s3.eu-west-1.amazonaws.com/vendor-templates/agent.yaml" }
  }

  expect_failures = [check.template_url_not_version_pinned]
}

run "warns_for_an_unpinned_govcloud_url" {
  command = plan

  variables {
    template = { url = "https://vendor-templates.s3.us-gov-west-1.amazonaws.com/agent.yaml" }
  }

  expect_failures = [check.template_url_not_version_pinned]
}

run "warns_for_an_unpinned_china_url" {
  command = plan

  variables {
    template = { url = "https://s3.cn-north-1.amazonaws.com.cn/vendor-templates/agent.yaml" }
  }

  expect_failures = [check.template_url_not_version_pinned]
}

run "warns_when_version_id_is_only_part_of_the_key" {
  command = plan

  variables {
    # versionId= in the path is not a query parameter: S3 ignores it.
    template = { url = "https://vendor-templates.s3.amazonaws.com/agent/versionId=3/agent.yaml" }
  }

  expect_failures = [check.template_url_not_version_pinned]
}

run "is_silent_for_an_inline_template" {
  command = plan

  variables {
    template = { body = "{\"Resources\":{\"Handle\":{\"Type\":\"AWS::CloudFormation::WaitConditionHandle\"}}}" }
  }

  assert {
    condition     = !local.template_url_unpinned && !local.template_body_not_a_mapping
    error_message = "An inline template has no URL to pin and must not warn."
  }
}

# A non-S3 URL, such as an internal artifact server, never reaches the check:
# CloudFormation reads TemplateURL only from S3, and the url validation
# already rejects anything else at plan. The check's own S3 host pattern is
# the same one, so it can never flag a URL the validation lets through as
# non-S3.
run "never_checks_a_non_s3_url_because_validation_rejects_it" {
  command = plan

  variables {
    template = { url = "https://artifacts.internal.example.com/cfn/agent.yaml" }
  }

  expect_failures = [var.template]
}

# --- stack_policy.url -------------------------------------------------------

run "warns_for_an_unpinned_stack_policy_url" {
  command = plan

  variables {
    stack_policy = { url = "https://vendor-templates.s3.us-east-1.amazonaws.com/agent/policy.json" }
  }

  expect_failures = [check.stack_policy_url_not_version_pinned]
}

run "is_silent_for_a_version_pinned_stack_policy_url" {
  command = plan

  variables {
    stack_policy = { url = "https://vendor-templates.s3.us-east-1.amazonaws.com/agent/policy.json?versionId=Lp8q1" }
  }

  assert {
    condition     = aws_cloudformation_stack.this.policy_url == "https://vendor-templates.s3.us-east-1.amazonaws.com/agent/policy.json?versionId=Lp8q1" && !local.stack_policy_url_unpinned
    error_message = "A version-pinned stack policy URL must be sent unchanged and not warn."
  }
}

run "is_silent_for_an_inline_stack_policy" {
  command = plan

  variables {
    stack_policy = { body = "{\"Statement\":[{\"Effect\":\"Deny\",\"Action\":\"Update:Replace\",\"Principal\":\"*\",\"Resource\":\"*\"}]}" }
  }

  assert {
    condition     = !local.stack_policy_url_unpinned
    error_message = "An inline stack policy has no URL to pin."
  }
}

# --- template.body ----------------------------------------------------------

# Terraform's yamldecode rejects every CloudFormation short-form tag
# ("unsupported tag \"!Ref\""). The check must still accept a real template
# that uses them, in flow and block style, nested, and with !! standard tags.
run "is_silent_for_yaml_with_short_form_intrinsics" {
  command = plan

  variables {
    template = {
      body = <<-YAML
        AWSTemplateFormatVersion: "2010-09-09"
        Parameters:
          Env:
            Type: String
        Conditions:
          IsProd: !Equals [!Ref Env, prod]
        Resources:
          Bucket:
            Type: AWS::S3::Bucket
            Properties:
              BucketName: !Sub "$${AWS::StackName}-$${Env}"
          Parameter:
            Type: AWS::SSM::Parameter
            Condition: IsProd
            Properties:
              Type: String
              Name: !Sub /app/$${Env}/bucket-arn
              Value: !GetAtt Bucket.Arn
              Description: !Join
                - " "
                - - !Ref Bucket
                  - !If [IsProd, !GetAtt [Bucket, DomainName], !Ref "AWS::NoValue"]
              Tier: !!str Standard
        Outputs:
          BucketArn:
            Value: !GetAtt Bucket.Arn
            Condition: IsProd
      YAML
    }
  }

  assert {
    condition     = !local.template_body_not_a_mapping
    error_message = "Valid CloudFormation YAML with short-form intrinsics must not warn."
  }

  assert {
    condition     = !can(yamldecode(var.template.body))
    error_message = "This fixture must be one yamldecode alone rejects, or the run proves nothing."
  }
}

run "is_silent_for_a_json_template" {
  command = plan

  variables {
    template = { body = "{\n\t\"Resources\": {\n\t\t\"Handle\": {\"Type\": \"AWS::CloudFormation::WaitConditionHandle\"}\n\t}\n}" }
  }

  assert {
    condition     = !local.template_body_not_a_mapping
    error_message = "A JSON template (tab-indented, which YAML would refuse) must not warn."
  }
}

# Syntax errors (bad indentation, unclosed brackets or quotes, trailing
# commas in JSON) are not tested here: the provider rejects them at plan with
# a hard error before any check runs, from 6.35.0 on. The check covers what
# the provider accepts and the API does not: valid JSON or YAML that is not a
# mapping.

run "warns_for_a_file_path_passed_without_file" {
  command = plan

  variables {
    template = { body = "templates/vendor-agent.yaml" }
  }

  expect_failures = [check.template_body_not_a_mapping]
}

run "warns_for_a_yaml_list" {
  command = plan

  variables {
    template = { body = "- Resources:\n    Handle:\n      Type: AWS::CloudFormation::WaitConditionHandle\n" }
  }

  expect_failures = [check.template_body_not_a_mapping]
}

run "warns_for_a_json_string" {
  command = plan

  variables {
    template = { body = "\"{\\\"Resources\\\": {}}\"" }
  }

  expect_failures = [check.template_body_not_a_mapping]
}
