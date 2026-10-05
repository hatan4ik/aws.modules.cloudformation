variable "name" {
  description = "StackSet name. Same rules as a stack name: starts with a letter, then letters, digits, and hyphens only, 128 characters at most, unique per administrator account and region. Changing it replaces the StackSet and every instance."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{0,127}$", var.name))
    error_message = "name must start with a letter and contain only letters, digits, and hyphens, 128 characters at most (CloudFormation StackSet name rules)."
  }
}

variable "description" {
  description = "Optional StackSet description, 1 to 1,024 characters. null (the default) sets none."
  type        = string
  default     = null

  validation {
    condition     = var.description == null ? true : (length(var.description) >= 1 && length(var.description) <= 1024)
    error_message = "description must be 1 to 1,024 characters, or null."
  }
}

variable "template" {
  description = "Template source: exactly one of body (an inline JSON or YAML template, 1 to 51,200 bytes) or url (an https:// URL of a template object in Amazon S3, up to 5,120 characters; the object itself may be up to 1 MB). Same shape and rules as the root module's template."
  type = object({
    body = optional(string)
    url  = optional(string)
  })
  nullable = false

  validation {
    condition     = (var.template.body == null) != (var.template.url == null)
    error_message = "template needs exactly one of body or url: CloudFormation accepts TemplateBody or TemplateURL, never both and never neither."
  }

  validation {
    # Exact UTF-8 byte count: base64 encodes 3 bytes as 4 characters, minus padding.
    condition = var.template.body == null ? true : (
      length(var.template.body) > 0 &&
      length(base64encode(var.template.body)) / 4 * 3 - length(regex("=*$", base64encode(var.template.body))) <= 51200
    )
    error_message = "template.body must be 1 to 51,200 bytes (the CloudFormation TemplateBody quota). Upload a larger template to S3 and pass template.url instead."
  }

  validation {
    condition = var.template.url == null ? true : (
      length(var.template.url) <= 5120 &&
      can(regex("^https://([a-z0-9][a-z0-9.-]*\\.)?s3([.-][a-z0-9-]+)*\\.amazonaws\\.com(\\.cn)?/[^[:space:]]+$", var.template.url)) &&
      # Website endpoints only: <bucket>.s3-website-<region> or
      # <bucket>.s3-website.<region>, matched on the host so an object key
      # such as templates/s3-website.yaml is not rejected.
      !can(regex("^https://([^/]*\\.)?s3-website([.-][a-z0-9-]+)?\\.amazonaws\\.com(\\.cn)?/", var.template.url))
    )
    error_message = "template.url must be an https:// Amazon S3 object URL (virtual-hosted or path style) of at most 5,120 characters. S3 static website URLs are not accepted by CloudFormation."
  }
}

variable "parameters" {
  description = "Template parameter values for every instance, as strings. Declare every template parameter here, including ones with a Default: the provider does not read template defaults back for a StackSet, so an omitted one shows a diff on every plan. Values are stored in plan and state in clear text; NoEcho parameters are not supported (see README)."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = length(var.parameters) <= 200
    error_message = "parameters may hold at most 200 entries (the CloudFormation per-template parameter quota)."
  }

  validation {
    condition     = alltrue([for key in keys(var.parameters) : can(regex("^[A-Za-z0-9]{1,255}$", key))])
    error_message = "Parameter names must be 1 to 255 alphanumeric characters, as CloudFormation logical IDs are."
  }

  validation {
    condition     = alltrue([for value in values(var.parameters) : length(value) <= 4096])
    error_message = "Each parameter value must be at most 4,096 characters (the CloudFormation parameter value quota is 4,096 bytes)."
  }
}

variable "capabilities" {
  description = "Capabilities the template needs acknowledged: CAPABILITY_IAM, CAPABILITY_NAMED_IAM, CAPABILITY_AUTO_EXPAND. CloudFormation accepts CAPABILITY_AUTO_EXPAND for either permission model, but a service-managed StackSet cannot run macros or transforms (including AWS::Serverless and AWS::Include): a template that references one fails at apply even with the capability. The module cannot detect a macro in the template, so expand it first or use self_managed."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for capability in var.capabilities : contains(["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"], capability)])
    error_message = "capabilities may contain only CAPABILITY_IAM, CAPABILITY_NAMED_IAM, and CAPABILITY_AUTO_EXPAND."
  }
}

variable "permission_model" {
  description = <<-EOT
    How StackSets gets permission to deploy into target accounts. Set exactly one branch; each carries only the inputs its model accepts, so an input of the other model cannot be expressed.

    self_managed: you created the roles. administration_role_arn (required) is the role in this administrator account that CloudFormation assumes; execution_role_name (default AWSCloudFormationStackSetExecutionRole) is the role it then assumes in every target account. Targets are account IDs.

    service_managed: AWS Organizations trusted access creates the roles. auto_deployment (required) decides whether accounts that join a targeted OU get an instance automatically (enabled) and whether their stacks are kept when they leave (retain_stacks_on_account_removal, default false). call_as is SELF (default; running in the management account) or DELEGATED_ADMIN (running in a registered delegated administrator account). Targets are OU IDs or the organization root ID. Changing auto_deployment replaces the StackSet.
  EOT
  type = object({
    self_managed = optional(object({
      administration_role_arn = string
      execution_role_name     = optional(string, "AWSCloudFormationStackSetExecutionRole")
    }))
    service_managed = optional(object({
      auto_deployment = object({
        enabled                          = bool
        retain_stacks_on_account_removal = optional(bool, false)
      })
      call_as = optional(string, "SELF")
    }))
  })
  nullable = false

  validation {
    condition     = (var.permission_model.self_managed == null) != (var.permission_model.service_managed == null)
    error_message = "permission_model needs exactly one of self_managed or service_managed."
  }

  validation {
    condition     = var.permission_model.self_managed == null ? true : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]{1,512}$", var.permission_model.self_managed.administration_role_arn))
    error_message = "permission_model.self_managed.administration_role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<path/name>)."
  }

  validation {
    condition     = var.permission_model.self_managed == null ? true : can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", var.permission_model.self_managed.execution_role_name))
    error_message = "permission_model.self_managed.execution_role_name must be an IAM role name: 1 to 64 characters of letters, digits, and _+=,.@- (no path)."
  }

  validation {
    condition     = var.permission_model.service_managed == null ? true : contains(["SELF", "DELEGATED_ADMIN"], var.permission_model.service_managed.call_as)
    error_message = "permission_model.service_managed.call_as must be SELF or DELEGATED_ADMIN."
  }
}

variable "stack_instances" {
  description = <<-EOT
    Stack instances keyed "<target>/<region>", one aws_cloudformation_stack_set_instance each. The key is the instance's identity, so the same target and region cannot be declared twice. The target is a 12-digit account ID for self_managed, or an OU ID (ou-xxxx-yyyyyyyy) or the organization root ID (r-xxxx) for service_managed, which deploys to every account in it. The region is where the instance stack is created.

    parameter_overrides replaces StackSet parameter values for this instance only. retain_stack = true keeps the deployed stack in the target account when the instance is removed (the stack is disassociated, not deleted). Changing a key replaces that instance.
  EOT
  type = map(object({
    parameter_overrides = optional(map(string), {})
    retain_stack        = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for key in keys(var.stack_instances) : can(regex("^([0-9]{12}|ou-[0-9a-z]{4,32}-[a-z0-9]{8,32}|r-[0-9a-z]{4,32})/[a-z]{2}-(gov-|iso-|isob-)?[a-z]+-[0-9]$", key))])
    error_message = "Each stack_instances key must be \"<target>/<region>\": a 12-digit account ID, an OU ID (ou-xxxx-yyyyyyyy), or a root ID (r-xxxx), then a slash and an AWS region such as us-east-1."
  }

  validation {
    condition     = alltrue([for instance in values(var.stack_instances) : alltrue([for key in keys(instance.parameter_overrides) : can(regex("^[A-Za-z0-9]{1,255}$", key))])])
    error_message = "parameter_overrides names must be 1 to 255 alphanumeric characters."
  }
}

variable "operation_preferences" {
  description = <<-EOT
    How far and how fast one StackSet operation rolls out, which bounds the blast radius of a bad template. Unset fields keep the CloudFormation defaults: failure tolerance 0 and one account at a time, the slowest and safest rollout.

    failure_tolerance_count or failure_tolerance_percentage (at most one): failures per region tolerated before CloudFormation stops the operation in that region and skips later regions. max_concurrent_count or max_concurrent_percentage (at most one): accounts worked on at once. concurrency_mode: STRICT_FAILURE_TOLERANCE (the API default; concurrency never exceeds failure tolerance + 1) or SOFT_FAILURE_TOLERANCE. region_concurrency_type (SEQUENTIAL or PARALLEL) and region_order: how regions are ordered within one operation.

    The StackSet's settings govern template and parameter updates, which roll out to every existing instance in one operation. Each instance resource applies the account-level settings and concurrency_mode to its own create, update, and delete; region_order and region_concurrency_type do not apply there, because each instance targets one region.
  EOT
  type = object({
    failure_tolerance_count      = optional(number)
    failure_tolerance_percentage = optional(number)
    max_concurrent_count         = optional(number)
    max_concurrent_percentage    = optional(number)
    concurrency_mode             = optional(string)
    region_concurrency_type      = optional(string)
    region_order                 = optional(list(string))
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.operation_preferences.failure_tolerance_count == null || var.operation_preferences.failure_tolerance_percentage == null
    error_message = "Set at most one of operation_preferences.failure_tolerance_count and failure_tolerance_percentage."
  }

  validation {
    condition     = var.operation_preferences.max_concurrent_count == null || var.operation_preferences.max_concurrent_percentage == null
    error_message = "Set at most one of operation_preferences.max_concurrent_count and max_concurrent_percentage."
  }

  validation {
    condition = alltrue([
      var.operation_preferences.failure_tolerance_count == null ? true : var.operation_preferences.failure_tolerance_count >= 0 && floor(var.operation_preferences.failure_tolerance_count) == var.operation_preferences.failure_tolerance_count,
      var.operation_preferences.failure_tolerance_percentage == null ? true : var.operation_preferences.failure_tolerance_percentage >= 0 && var.operation_preferences.failure_tolerance_percentage <= 100 && floor(var.operation_preferences.failure_tolerance_percentage) == var.operation_preferences.failure_tolerance_percentage,
      var.operation_preferences.max_concurrent_count == null ? true : var.operation_preferences.max_concurrent_count >= 1 && floor(var.operation_preferences.max_concurrent_count) == var.operation_preferences.max_concurrent_count,
      var.operation_preferences.max_concurrent_percentage == null ? true : var.operation_preferences.max_concurrent_percentage >= 1 && var.operation_preferences.max_concurrent_percentage <= 100 && floor(var.operation_preferences.max_concurrent_percentage) == var.operation_preferences.max_concurrent_percentage,
    ])
    error_message = "operation_preferences ranges: failure_tolerance_count is a whole number >= 0, failure_tolerance_percentage 0-100, max_concurrent_count >= 1, max_concurrent_percentage 1-100 (whole numbers)."
  }

  validation {
    condition     = var.operation_preferences.concurrency_mode == null ? true : contains(["STRICT_FAILURE_TOLERANCE", "SOFT_FAILURE_TOLERANCE"], var.operation_preferences.concurrency_mode)
    error_message = "operation_preferences.concurrency_mode must be STRICT_FAILURE_TOLERANCE or SOFT_FAILURE_TOLERANCE."
  }

  validation {
    condition     = var.operation_preferences.region_concurrency_type == null ? true : contains(["SEQUENTIAL", "PARALLEL"], var.operation_preferences.region_concurrency_type)
    error_message = "operation_preferences.region_concurrency_type must be SEQUENTIAL or PARALLEL."
  }

  validation {
    condition = var.operation_preferences.region_order == null ? true : (
      alltrue([for region in var.operation_preferences.region_order : can(regex("^[a-z]{2}-(gov-|iso-|isob-)?[a-z]+-[0-9]$", region))]) &&
      length(distinct(var.operation_preferences.region_order)) == length(var.operation_preferences.region_order)
    )
    error_message = "operation_preferences.region_order must list distinct AWS regions such as us-east-1."
  }
}

variable "managed_execution_active" {
  description = "Whether StackSets runs non-conflicting operations concurrently and queues conflicting ones. true by default, unlike the API: Terraform creates the instances of one StackSet in parallel, and without managed execution the second concurrent operation fails with OperationInProgressException."
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "Tags applied to the StackSet, which CloudFormation propagates to every instance stack and to the supported resources in them. The module adds Name = name; a Name given here wins. At most 50 tags in total including Name (provider default_tags also count). Keys 1 to 128 and values 1 to 256 characters of letters, digits, spaces, and _ . : / = + - @; no aws: key prefix."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = length(merge({ Name = "" }, var.tags)) <= 50
    error_message = "A StackSet takes at most 50 tags, and the module adds Name unless tags already sets it."
  }

  validation {
    condition     = alltrue([for key in keys(var.tags) : !startswith(lower(key), "aws:")])
    error_message = "Tag keys may not start with the reserved aws: prefix."
  }

  validation {
    # CloudFormation Tag: key 1-128 and value 1-256 characters. The character
    # set is the common AWS tagging one; tags propagate to the resources in
    # the stack, whose services enforce it. Matches aws.modules.resource-groups.
    condition = alltrue([
      for key, value in var.tags :
      length(key) >= 1 && length(key) <= 128 && can(regex("^[\\p{L}\\p{Z}\\p{N}_.:/=+\\-@]+$", key)) &&
      length(value) >= 1 && length(value) <= 256 && can(regex("^[\\p{L}\\p{Z}\\p{N}_.:/=+\\-@]+$", value))
    ])
    error_message = "Tag keys must be 1 to 128 characters and values 1 to 256 (CloudFormation rejects empty values), both of letters, digits, spaces, and _ . : / = + - @."
  }
}

variable "timeouts" {
  description = "Terraform-side waits as Go durations such as \"2h\": stack_set_update for template and parameter rollouts across every instance, and instance_create, instance_update, instance_delete for each instance resource. Unset fields keep the provider defaults (30m each), which a rollout across many accounts can exceed."
  type = object({
    stack_set_update = optional(string)
    instance_create  = optional(string)
    instance_update  = optional(string)
    instance_delete  = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for value in [var.timeouts.stack_set_update, var.timeouts.instance_create, var.timeouts.instance_update, var.timeouts.instance_delete] :
      value == null ? true : can(regex("^([0-9]+(\\.[0-9]+)?(h|m|s))+$", value))
    ])
    error_message = "Each timeouts field must be a Go duration such as \"30m\", \"2h\", or \"1h30m\"."
  }
}
