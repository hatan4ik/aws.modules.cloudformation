provider "aws" {
  region = var.region
}

module "audit_role_baseline" {
  source = "../../modules/stack-set"

  name        = var.name
  description = "Security audit role in every member account"
  template    = { body = file("${path.module}/baseline.yaml") }

  # Every template parameter, including RoleName, which has a Default: the
  # provider does not read template defaults back for a StackSet.
  parameters = {
    SecurityAccountId = var.security_account_id
    RoleName          = "security-audit"
  }
  capabilities = ["CAPABILITY_NAMED_IAM"]

  # AWS Organizations creates the deployment roles. Accounts that join a
  # targeted OU get the role automatically; an account that leaves keeps it
  # only if retain_stacks_on_account_removal is true.
  permission_model = {
    service_managed = {
      auto_deployment = { enabled = true, retain_stacks_on_account_removal = false }
      call_as         = var.call_as
    }
  }

  # One instance per OU and region. IAM is global, so one region is enough
  # for a role; a regional baseline (AWS Config, GuardDuty) lists every
  # region it must cover.
  stack_instances = {
    for ou in var.organizational_unit_ids : "${ou}/${var.region}" => {}
  }

  # The blast radius of a bad template: roll out to at most two accounts in
  # a region at a time, and stop the whole operation as soon as more than one
  # account in a region fails. Under the default STRICT_FAILURE_TOLERANCE
  # mode, concurrency cannot exceed failure tolerance + 1, so 2 is the most
  # this tolerance allows. For a large organization, max_concurrent_percentage
  # (for example 10) scales with the OU instead. Regions go one after another,
  # home region first, so a broken template is caught before it reaches the
  # rest.
  operation_preferences = {
    failure_tolerance_count = 1
    max_concurrent_count    = 2
    region_concurrency_type = "SEQUENTIAL"
    region_order            = [var.region]
  }

  timeouts = {
    stack_set_update = "2h"
    instance_create  = "1h"
  }

  tags = {
    Environment = "example"
    Owner       = "security"
  }
}
