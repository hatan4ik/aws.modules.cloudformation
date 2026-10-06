# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended.

# The failure this module exists to prevent: a service role that can do
# anything, because working out what the template needs was skipped.
check "statement_allows_every_action" {
  assert {
    condition     = !anytrue([for statement in values(var.statements) : statement.effect == "Allow" && contains(statement.actions, "*")])
    error_message = "A statement allows every action (\"*\"), so any stack that uses this role, and anyone who may update such a stack, can do anything in the account. List the actions the template's resource types need (their registry schema handlers) instead."
  }
}

# iam:PassRole on every role is a privilege escalation path: the stack can
# hand any role in the account to the listed services.
check "pass_role_to_any_role" {
  assert {
    condition     = !anytrue(flatten([for grant in values(var.pass_roles) : [for arn in grant.role_arns : can(regex(":role/\\*$", arn))]]))
    error_message = "A pass_roles grant names role/* (every role in the account). Name the roles the template passes, or a prefix such as role/<stack name>-* for roles it creates."
  }
}
