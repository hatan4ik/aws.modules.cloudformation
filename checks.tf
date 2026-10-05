# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended.

check "service_role_not_set" {
  assert {
    condition     = var.iam_role_arn != null
    error_message = "iam_role_arn is not set, so CloudFormation operates this stack with the credentials of whoever runs Terraform. Pass a least-privilege service role so the stack's permissions are explicit, auditable, and independent of the caller."
  }
}

# A template_url is a static string. Overwriting the S3 object behind it
# changes nothing Terraform compares, so the stack is never updated to the new
# content. A ?versionId= URL changes whenever the object does. See
# docs/DESIGN.md D14.
check "template_url_not_version_pinned" {
  assert {
    condition     = !local.template_url_unpinned
    error_message = "template.url is an S3 object URL without ?versionId=. If the object is overwritten, Terraform sees no change and never updates the stack to the new template. Enable versioning on the bucket and pin the version (for example ?versionId=$${aws_s3_object.template.version_id}), or use template.body. See README, Template immutability."
  }
}

# Same drift for the stack policy: an overwritten policy object is never
# re-applied.
check "stack_policy_url_not_version_pinned" {
  assert {
    condition     = !local.stack_policy_url_unpinned
    error_message = "stack_policy.url is an S3 object URL without ?versionId=. If the object is overwritten, Terraform sees no change and never re-applies the stack policy. Pin the object version, or use stack_policy.body. See README, Template immutability."
  }
}

# Syntax errors in a body already fail at plan in the provider. This catches
# the valid JSON or YAML that is still not a template, before the API does.
# Advisory, because the short-form tag handling is a heuristic and
# CloudFormation's parser is the authority. See docs/DESIGN.md D16.
check "template_body_not_a_mapping" {
  assert {
    condition     = !local.template_body_not_a_mapping
    error_message = "template.body parses, but not as a JSON or YAML mapping (CloudFormation short-form tags such as !Ref are accounted for), so it cannot be a template and CloudFormation will reject it at apply. The usual cause is a file path passed as the body: write body = file(\"stack.yaml\"), not body = \"stack.yaml\"."
  }
}
