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
