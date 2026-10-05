# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended.

# AWS's sample execution role attaches AdministratorAccess and the AWS guide
# says to scope it down afterwards. The module never attaches it by default;
# this warns when a caller does.
check "execution_role_administrator_access" {
  assert {
    condition     = var.role.execution == null ? true : !anytrue([for arn in values(var.role.execution.policy_arns) : can(regex(":iam::aws:policy/AdministratorAccess$", arn))])
    error_message = "The execution role gets AdministratorAccess, so any StackSet run through the trusted administration role can do anything in this account. Grant only what the StackSet's template creates, through inline_policy or a scoped managed policy."
  }
}
