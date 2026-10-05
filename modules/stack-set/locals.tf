locals {
  self_managed     = var.permission_model.self_managed != null
  permission_model = local.self_managed ? "SELF_MANAGED" : "SERVICE_MANAGED"

  # call_as exists only for service-managed StackSets; self-managed ones send
  # nothing and get the API default.
  call_as = local.self_managed ? null : var.permission_model.service_managed.call_as

  # The module adds only a Name tag, and a caller's Name wins.
  tags = merge({ Name = var.name }, var.tags)

  # Each key is "<target>/<region>"; split once here so the target and region
  # an instance uses can never drift from what its key says.
  stack_instances = {
    for key, instance in var.stack_instances : key => merge(instance, {
      target = split("/", key)[0]
      region = split("/", key)[1]
    })
  }

  # Targets of the wrong shape for the permission model, named in the
  # precondition on the StackSet.
  mismatched_instance_keys = sort([
    for key, instance in local.stack_instances : key
    if local.self_managed != can(regex("^[0-9]{12}$", instance.target))
  ])

  stack_set_operation_preferences = {
    for name, value in var.operation_preferences : name => value
    if value != null && name != "concurrency_mode"
  }

  # An instance targets one region, so region ordering does not apply to it;
  # concurrency_mode exists only on instance operations in the provider.
  instance_operation_preferences = {
    for name, value in var.operation_preferences : name => value
    if value != null && !contains(["region_concurrency_type", "region_order"], name)
  }
}
