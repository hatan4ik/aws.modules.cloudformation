# The template advisory checks, the same as the root module's:
# template_url_not_version_pinned (docs/DESIGN.md D14) and
# template_body_not_a_mapping (D16). A run without expect_failures fails on
# any check that fires, so each silent run proves every check stays quiet.

mock_provider "aws" {}

variables {
  name     = "baseline-config"
  template = { url = "https://baseline-templates.s3.us-east-1.amazonaws.com/config.yaml?versionId=Kq2c8eTP" }

  permission_model = {
    self_managed = {
      administration_role_arn = "arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"
    }
  }

  stack_instances = {
    "222222222222/us-east-1" = {}
  }
}

run "is_silent_for_a_version_pinned_s3_url" {
  command = plan

  assert {
    condition     = aws_cloudformation_stack_set.this.template_url == "https://baseline-templates.s3.us-east-1.amazonaws.com/config.yaml?versionId=Kq2c8eTP"
    error_message = "A version-pinned URL must be sent unchanged, query string included."
  }
}

run "warns_for_an_unpinned_virtual_hosted_url" {
  command = plan

  variables {
    template = { url = "https://baseline-templates.s3.us-east-1.amazonaws.com/config.yaml" }
  }

  expect_failures = [check.template_url_not_version_pinned]
}

run "warns_for_an_unpinned_path_style_url" {
  command = plan

  variables {
    template = { url = "https://s3.us-gov-west-1.amazonaws.com/baseline-templates/config.yaml" }
  }

  expect_failures = [check.template_url_not_version_pinned]
}

run "warns_for_an_unpinned_china_url" {
  command = plan

  variables {
    template = { url = "https://baseline-templates.s3.cn-northwest-1.amazonaws.com.cn/config.yaml" }
  }

  expect_failures = [check.template_url_not_version_pinned]
}

# CloudFormation reads TemplateURL only from S3, and the url validation
# rejects anything else at plan, so a non-S3 URL never reaches the check.
run "never_checks_a_non_s3_url_because_validation_rejects_it" {
  command = plan

  variables {
    template = { url = "https://artifacts.internal.example.com/cfn/config.yaml" }
  }

  expect_failures = [var.template]
}

run "is_silent_for_yaml_with_short_form_intrinsics" {
  command = plan

  variables {
    template = {
      body = <<-YAML
        AWSTemplateFormatVersion: "2010-09-09"
        Parameters:
          RecorderName:
            Type: String
        Resources:
          Topic:
            Type: AWS::SNS::Topic
            Properties:
              TopicName: !Sub "$${RecorderName}-$${AWS::Region}"
          Parameter:
            Type: AWS::SSM::Parameter
            Properties:
              Type: String
              Value: !GetAtt [Topic, TopicArn]
              Name: !Join ["/", ["", baseline, !Ref RecorderName]]
      YAML
    }
    parameters = { RecorderName = "baseline" }
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.template_url == null && !can(yamldecode(var.template.body))
    error_message = "Valid CloudFormation YAML that yamldecode alone rejects must not warn."
  }
}

run "warns_for_a_file_path_passed_without_file" {
  command = plan

  variables {
    template = { body = "baseline.yaml" }
  }

  expect_failures = [check.template_body_not_a_mapping]
}
