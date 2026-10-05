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

  # Inputs of the template advisory checks in checks.tf, the same as the root
  # module's; see docs/DESIGN.md D14 and D16. S3 object URL hosts, as the url
  # validation accepts them: virtual-hosted, path style, dualstack and FIPS,
  # GovCloud, and China (amazonaws.com.cn).
  s3_url_pattern        = "^https://([a-z0-9][a-z0-9.-]*\\.)?s3([.-][a-z0-9-]+)*\\.amazonaws\\.com(\\.cn)?/"
  s3_version_id_pattern = "[?&]versionId=[^&#]+"
  template_url_unpinned = var.template.url == null ? false : can(regex(local.s3_url_pattern, var.template.url)) && !can(regex(local.s3_version_id_pattern, var.template.url))

  # yamldecode rejects CloudFormation short-form tags (!Ref, !GetAtt, ...);
  # removing a local tag leaves the tagged value as plain YAML.
  cfn_short_form_tag_pattern = "/(^|[\\s\\[{,])![A-Za-z][A-Za-z0-9:]*/"
  template_body_not_a_mapping = var.template.body == null ? false : !(
    can(keys(jsondecode(var.template.body))) ||
    can(keys(yamldecode(replace(var.template.body, local.cfn_short_form_tag_pattern, "$1"))))
  )
}
