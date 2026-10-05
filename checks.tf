# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended.

check "service_role_not_set" {
  assert {
    condition     = var.iam_role_arn != null
    error_message = "iam_role_arn is not set, so CloudFormation operates this stack with the credentials of whoever runs Terraform. Pass a least-privilege service role so the stack's permissions are explicit, auditable, and independent of the caller."
  }
}
