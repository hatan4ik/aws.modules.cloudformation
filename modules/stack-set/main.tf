resource "aws_cloudformation_stack_set" "this" {
  name        = var.name
  description = var.description

  template_body = var.template.body
  template_url  = var.template.url
  parameters    = var.parameters
  capabilities  = var.capabilities

  permission_model        = local.permission_model
  administration_role_arn = try(var.permission_model.self_managed.administration_role_arn, null)
  execution_role_name     = try(var.permission_model.self_managed.execution_role_name, null)
  call_as                 = local.call_as

  dynamic "auto_deployment" {
    for_each = local.self_managed ? [] : [var.permission_model.service_managed.auto_deployment]

    content {
      enabled                          = auto_deployment.value.enabled
      retain_stacks_on_account_removal = auto_deployment.value.retain_stacks_on_account_removal
    }
  }

  managed_execution {
    active = var.managed_execution_active
  }

  # Governs UpdateStackSet: a template or parameter change rolls out to every
  # existing instance in one operation, bounded by these settings.
  dynamic "operation_preferences" {
    for_each = length(local.stack_set_operation_preferences) > 0 ? [var.operation_preferences] : []

    content {
      failure_tolerance_count      = operation_preferences.value.failure_tolerance_count
      failure_tolerance_percentage = operation_preferences.value.failure_tolerance_percentage
      max_concurrent_count         = operation_preferences.value.max_concurrent_count
      max_concurrent_percentage    = operation_preferences.value.max_concurrent_percentage
      region_concurrency_type      = operation_preferences.value.region_concurrency_type
      region_order                 = operation_preferences.value.region_order
    }
  }

  tags = local.tags

  timeouts {
    update = var.timeouts.stack_set_update
  }

  lifecycle {
    precondition {
      condition     = length(local.mismatched_instance_keys) == 0
      error_message = "stack_instances targets must match the permission model: 12-digit account IDs for self_managed, OU IDs (ou-...) or the root ID (r-...) for service_managed. Mismatched keys: ${join(", ", local.mismatched_instance_keys)}."
    }
  }
}

resource "aws_cloudformation_stack_set_instance" "this" {
  for_each = local.stack_instances

  stack_set_name            = aws_cloudformation_stack_set.this.name
  stack_set_instance_region = each.value.region
  call_as                   = local.call_as

  # Self-managed: one account. Service-managed: every account in one OU or
  # in the whole organization (root ID).
  account_id = local.self_managed ? each.value.target : null

  dynamic "deployment_targets" {
    for_each = local.self_managed ? [] : [each.value.target]

    content {
      organizational_unit_ids = [deployment_targets.value]
    }
  }

  parameter_overrides = length(each.value.parameter_overrides) > 0 ? each.value.parameter_overrides : null
  retain_stack        = each.value.retain_stack

  dynamic "operation_preferences" {
    for_each = length(local.instance_operation_preferences) > 0 ? [var.operation_preferences] : []

    content {
      failure_tolerance_count      = operation_preferences.value.failure_tolerance_count
      failure_tolerance_percentage = operation_preferences.value.failure_tolerance_percentage
      max_concurrent_count         = operation_preferences.value.max_concurrent_count
      max_concurrent_percentage    = operation_preferences.value.max_concurrent_percentage
      concurrency_mode             = operation_preferences.value.concurrency_mode
    }
  }

  timeouts {
    create = var.timeouts.instance_create
    update = var.timeouts.instance_update
    delete = var.timeouts.instance_delete
  }
}
