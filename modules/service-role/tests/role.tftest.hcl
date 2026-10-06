# The role, its trust policy, and the template policy rendered from the
# caller's statements.

mock_provider "aws" {}

variables {
  name       = "cloudformation-artifacts"
  account_id = "123456789012"
  statements = {
    SsmParameter = {
      actions   = ["ssm:PutParameter", "ssm:DeleteParameter", "ssm:GetParameters", "ssm:AddTagsToResource"]
      resources = ["arn:aws:ssm:us-east-1:123456789012:parameter/artifacts/*"]
    }
  }
}

run "renders_a_minimal_service_role" {
  command = plan

  assert {
    condition     = aws_iam_role.this.name == "cloudformation-artifacts" && aws_iam_role.this.path == "/" && aws_iam_role.this.permissions_boundary == null
    error_message = "The role must take name, default to path /, and set no permissions boundary by default."
  }

  assert {
    condition = jsondecode(aws_iam_role.this.assume_role_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Service = "cloudformation.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEqualsIfExists = { "aws:SourceAccount" = "123456789012" }
          ArnLikeIfExists      = { "aws:SourceArn" = "arn:*:cloudformation:*:123456789012:*" }
        }
      }]
    }
    error_message = "Only CloudFormation may assume the role, with the confused-deputy conditions bound to this account (IfExists, see docs/DESIGN.md D15)."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.template.policy) == {
      Version = "2012-10-17"
      Statement = [{
        Sid      = "SsmParameter"
        Effect   = "Allow"
        Action   = ["ssm:AddTagsToResource", "ssm:DeleteParameter", "ssm:GetParameters", "ssm:PutParameter"]
        Resource = ["arn:aws:ssm:us-east-1:123456789012:parameter/artifacts/*"]
      }]
    }
    error_message = "The template policy must be exactly the caller's statement, with sorted actions and no Condition when none is given."
  }

  assert {
    condition     = aws_iam_role_policy.template.name == "CloudFormationTemplate" && length(aws_iam_role_policy.pass_role) == 0
    error_message = "One inline template policy, and no pass-role policy unless pass_roles is set."
  }

  assert {
    condition     = aws_iam_role.this.tags == tomap({ Name = "cloudformation-artifacts" }) && startswith(aws_iam_role.this.description, "CloudFormation service role")
    error_message = "The module must add exactly one tag (Name) and a default description."
  }
}

run "renders_every_optional_input" {
  command = plan

  variables {
    path                     = "/cloudformation/"
    description              = "Deploys the artifacts stack."
    permissions_boundary_arn = "arn:aws:iam::123456789012:policy/cloudformation-boundary"
    tags                     = { Name = "custom", Owner = "platform" }
    statements = {
      S3Bucket = {
        actions   = ["s3:CreateBucket", "s3:DeleteBucket"]
        resources = ["arn:aws:s3:::artifacts-*"]
        conditions = [
          { test = "StringEquals", variable = "aws:RequestedRegion", values = ["us-east-1"] },
          { test = "StringEquals", variable = "aws:ResourceAccount", values = ["123456789012"] },
          { test = "Bool", variable = "aws:SecureTransport", values = ["true"] },
        ]
      }
      DenyIam = {
        effect    = "Deny"
        actions   = ["iam:*"]
        resources = ["*"]
      }
    }
  }

  assert {
    condition     = aws_iam_role.this.path == "/cloudformation/" && aws_iam_role.this.description == "Deploys the artifacts stack." && aws_iam_role.this.permissions_boundary == "arn:aws:iam::123456789012:policy/cloudformation-boundary"
    error_message = "path, description, and permissions_boundary_arn must pass through."
  }

  assert {
    condition     = aws_iam_role.this.tags == tomap({ Name = "custom", Owner = "platform" })
    error_message = "A caller's Name tag must win."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.template.policy).Statement == [
      { Sid = "DenyIam", Effect = "Deny", Action = ["iam:*"], Resource = ["*"] },
      {
        Sid      = "S3Bucket"
        Effect   = "Allow"
        Action   = ["s3:CreateBucket", "s3:DeleteBucket"]
        Resource = ["arn:aws:s3:::artifacts-*"]
        Condition = {
          StringEquals = { "aws:RequestedRegion" = ["us-east-1"], "aws:ResourceAccount" = ["123456789012"] }
          Bool         = { "aws:SecureTransport" = ["true"] }
        }
      },
    ]
    error_message = "Statements must render in Sid order, Deny included, with conditions grouped by test."
  }
}
