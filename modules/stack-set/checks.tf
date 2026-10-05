# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended.

check "no_stack_instances" {
  assert {
    condition     = length(var.stack_instances) > 0
    error_message = "stack_instances is empty, so the StackSet deploys nothing. Service-managed auto-deployment only reaches OUs that already have an instance; declare at least one \"<target>/<region>\" entry."
  }
}

# Under STRICT_FAILURE_TOLERANCE (the API default) CloudFormation never runs
# more accounts at once than failure tolerance + 1, so a larger
# max_concurrent_count does not take effect.
check "max_concurrency_capped_by_failure_tolerance" {
  assert {
    condition = (
      var.operation_preferences.concurrency_mode == "SOFT_FAILURE_TOLERANCE" ||
      var.operation_preferences.max_concurrent_count == null ||
      var.operation_preferences.failure_tolerance_count == null
      ) ? true : (
      var.operation_preferences.max_concurrent_count <= var.operation_preferences.failure_tolerance_count + 1
    )
    error_message = "max_concurrent_count is above failure_tolerance_count + 1 under STRICT_FAILURE_TOLERANCE, so CloudFormation caps the actual concurrency at failure_tolerance_count + 1. Raise the failure tolerance, lower max_concurrent_count, or set concurrency_mode = \"SOFT_FAILURE_TOLERANCE\" deliberately."
  }
}

# A template_url is a static string. Overwriting the S3 object behind it
# changes nothing Terraform compares, so the StackSet is never updated to the
# new content. A ?versionId= URL changes whenever the object does. See
# docs/DESIGN.md D14.
check "template_url_not_version_pinned" {
  assert {
    condition     = !local.template_url_unpinned
    error_message = "template.url is an S3 object URL without ?versionId=. If the object is overwritten, Terraform sees no change and never rolls the new template out to the StackSet. Enable versioning on the bucket and pin the version (for example ?versionId=$${aws_s3_object.template.version_id}), or use template.body. See the root README, Template immutability."
  }
}

# Syntax errors in a body already fail at plan in the provider. This catches
# the valid JSON or YAML that is still not a template. See docs/DESIGN.md D16.
check "template_body_not_a_mapping" {
  assert {
    condition     = !local.template_body_not_a_mapping
    error_message = "template.body parses, but not as a JSON or YAML mapping (CloudFormation short-form tags such as !Ref are accounted for), so it cannot be a template and CloudFormation will reject it at apply. The usual cause is a file path passed as the body: write body = file(\"stack.yaml\"), not body = \"stack.yaml\"."
  }
}
