# Integration suite: real apply in the caller's own account.
#
# Requires AWS credentials and a region from the environment (for example
# AWS_PROFILE and AWS_REGION, or the OIDC role assumed by the integration
# workflow). Nothing is hard-coded and no fixture is needed: the suite creates
# a stack whose only resource is an AWS::CloudFormation::WaitConditionHandle
# (a no-op placeholder that provisions nothing and costs nothing), with two
# Outputs, then updates a parameter in place, asserts what the real API
# reports, and deletes the stack at the end of the file.
#
# The stack runs with the caller's credentials (no iam_role_arn), so the
# service_role_not_set advisory check warns; that warning is expected here.
#
# Run: terraform init -backend=false -test-directory=tests/integration
#      terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl

provider "aws" {}

variables {
  name = "cfn-module-it-smoke"
  template = {
    body = <<-YAML
      AWSTemplateFormatVersion: "2010-09-09"
      Description: aws.modules.cloudformation integration smoke test. Safe to delete.
      Parameters:
        Greeting:
          Type: String
        Unused:
          Type: String
          Default: template-default
      Resources:
        Handle:
          Type: AWS::CloudFormation::WaitConditionHandle
      Outputs:
        Greeting:
          Value: !Ref Greeting
        StackRegion:
          Value: !Ref AWS::Region
    YAML
  }
  parameters = { Greeting = "hello" }
  tags = {
    IntegrationTest = "aws.modules.cloudformation"
    Disposable      = "true"
  }
}

run "creates_the_stack" {
  assert {
    condition     = can(regex("^arn:aws[a-z-]*:cloudformation:[a-z0-9-]+:[0-9]{12}:stack/cfn-module-it-smoke/[0-9a-f-]{36}$", output.arn)) && output.id == output.arn
    error_message = "arn must be the real stack ARN CloudFormation assigned, and id must equal it."
  }

  assert {
    condition     = output.name == "cfn-module-it-smoke"
    error_message = "name must be the stack name."
  }

  assert {
    condition     = output.outputs["Greeting"] == "hello" && length(output.outputs["StackRegion"]) > 0
    error_message = "outputs must carry the stack's real CloudFormation Outputs."
  }

  assert {
    condition     = keys(aws_cloudformation_stack.this.parameters) == ["Greeting"]
    error_message = "The provider must keep only declared parameters in state, so a template parameter left to its Default does not diff."
  }

  assert {
    condition     = aws_cloudformation_stack.this.tags["Name"] == "cfn-module-it-smoke" && aws_cloudformation_stack.this.tags["Disposable"] == "true"
    error_message = "The Name tag and the caller's tags must survive the real API."
  }
}

run "updates_a_parameter_in_place" {
  variables {
    parameters = { Greeting = "updated" }
  }

  assert {
    condition     = output.outputs["Greeting"] == "updated"
    error_message = "A parameter change must update the stack in place and refresh its Outputs."
  }

  assert {
    condition     = output.arn == run.creates_the_stack.arn
    error_message = "A parameter change must not replace the stack."
  }
}
