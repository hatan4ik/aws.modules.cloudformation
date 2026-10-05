variable "name" {
  description = "Stack name. CloudFormation rules: starts with a letter, then letters, digits, and hyphens only, 128 characters at most, unique per account and region. Changing it replaces the stack."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{0,127}$", var.name))
    error_message = "name must start with a letter and contain only letters, digits, and hyphens, 128 characters at most (CloudFormation stack name rules)."
  }
}

variable "template" {
  description = "Template source: exactly one of body (an inline JSON or YAML template, 1 to 51,200 bytes) or url (an https:// URL of a template object in Amazon S3, up to 5,120 characters; the object itself may be up to 1 MB). Write `template = { body = file(\"stack.yaml\") }` or `template = { url = \"https://...\" }`."
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
  description = "Template parameter values. Always strings on the wire: pass numbers as \"3\" and CommaDelimitedList values as \"a,b,c\". Values are stored in plan and state in clear text; never pass a secret here, resolve it in the template with a dynamic reference instead (see README, Security model)."
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
  description = "Capabilities the template needs acknowledged: CAPABILITY_IAM (creates IAM resources), CAPABILITY_NAMED_IAM (creates IAM resources with custom names), CAPABILITY_AUTO_EXPAND (uses macros or transforms, including AWS::Serverless). Empty by default, so a template that creates IAM resources fails with InsufficientCapabilities until the caller acknowledges it."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for capability in var.capabilities : contains(["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"], capability)])
    error_message = "capabilities may contain only CAPABILITY_IAM, CAPABILITY_NAMED_IAM, and CAPABILITY_AUTO_EXPAND."
  }
}

variable "on_failure" {
  description = "What CloudFormation does when stack creation fails: ROLLBACK (the stack ends in ROLLBACK_COMPLETE, which cannot be updated and must be replaced), DELETE (the failed stack is deleted), or DO_NOTHING (the stack stays in CREATE_FAILED with its partial resources, for debugging). null (the default) sends nothing, and CloudFormation applies ROLLBACK. Applies to creation only: CloudFormation never returns it, so the module ignores changes to it on an existing stack (no replacement), and an imported stack plans no change for any value."
  type        = string
  default     = null

  validation {
    condition     = var.on_failure == null ? true : contains(["ROLLBACK", "DELETE", "DO_NOTHING"], var.on_failure)
    error_message = "on_failure must be ROLLBACK, DELETE, or DO_NOTHING."
  }
}

variable "timeout_in_minutes" {
  description = "Minutes CloudFormation lets stack creation run before it fails the create and applies on_failure. null (the default) means no CloudFormation-side timeout. Changing it replaces the stack. Independent of the Terraform-side timeouts input."
  type        = number
  default     = null

  validation {
    condition     = var.timeout_in_minutes == null ? true : (var.timeout_in_minutes >= 1 && floor(var.timeout_in_minutes) == var.timeout_in_minutes)
    error_message = "timeout_in_minutes must be a whole number of at least 1, or null."
  }
}

variable "notification_arns" {
  description = "Amazon SNS topic ARNs that receive stack events, at most five. Empty by default."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.notification_arns) <= 5
    error_message = "notification_arns may hold at most 5 topic ARNs (CloudFormation's NotificationARNs limit)."
  }

  validation {
    condition     = alltrue([for arn in var.notification_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]{1,256}$", arn))])
    error_message = "Each notification_arns entry must be a standard SNS topic ARN (arn:<partition>:sns:<region>:<account>:<topic>)."
  }
}

variable "stack_policy" {
  description = "Optional stack policy that protects stack resources from unintended updates: exactly one of body (a JSON policy document, at most 16,384 bytes) or url (an https:// S3 object URL in the stack's region, at most 5,120 characters). null (the default) sets no stack policy, so every resource in the stack may be updated."
  type = object({
    body = optional(string)
    url  = optional(string)
  })
  default = null

  validation {
    condition     = var.stack_policy == null ? true : (var.stack_policy.body == null) != (var.stack_policy.url == null)
    error_message = "stack_policy needs exactly one of body or url when set: CloudFormation accepts StackPolicyBody or StackPolicyURL, never both. Use stack_policy = null for no policy."
  }

  validation {
    condition = var.stack_policy == null ? true : var.stack_policy.body == null ? true : (
      can(jsondecode(var.stack_policy.body)) &&
      length(base64encode(var.stack_policy.body)) / 4 * 3 - length(regex("=*$", base64encode(var.stack_policy.body))) <= 16384
    )
    error_message = "stack_policy.body must be a JSON document of at most 16,384 bytes."
  }

  validation {
    condition = var.stack_policy == null ? true : var.stack_policy.url == null ? true : (
      length(var.stack_policy.url) <= 5120 &&
      can(regex("^https://([a-z0-9][a-z0-9.-]*\\.)?s3([.-][a-z0-9-]+)*\\.amazonaws\\.com(\\.cn)?/[^[:space:]]+$", var.stack_policy.url)) &&
      # Website endpoints only: <bucket>.s3-website-<region> or
      # <bucket>.s3-website.<region>, matched on the host so an object key
      # such as templates/s3-website.yaml is not rejected.
      !can(regex("^https://([^/]*\\.)?s3-website([.-][a-z0-9-]+)?\\.amazonaws\\.com(\\.cn)?/", var.stack_policy.url))
    )
    error_message = "stack_policy.url must be an https:// Amazon S3 object URL of at most 5,120 characters. S3 static website URLs are not accepted by CloudFormation."
  }
}

variable "iam_role_arn" {
  description = "ARN of the service role CloudFormation assumes for every operation on this stack, so the stack's permissions are explicit and auditable instead of borrowed from whoever runs Terraform. null (the default) makes CloudFormation use the caller's credentials; the advisory check service_role_not_set warns about it. Once a stack has a role, CloudFormation keeps using it."
  type        = string
  default     = null

  validation {
    condition     = var.iam_role_arn == null ? true : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]{1,512}$", var.iam_role_arn))
    error_message = "iam_role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<path/name>)."
  }
}

variable "tags" {
  description = "Tags applied to the stack. CloudFormation propagates stack tags to every resource in the stack that supports tags. The module adds Name = name; a Name given here wins. At most 50 tags in total including Name (provider default_tags also count). Keys 1 to 128 and values 1 to 256 characters of letters, digits, spaces, and _ . : / = + - @; no aws: key prefix."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = length(merge({ Name = "" }, var.tags)) <= 50
    error_message = "A stack takes at most 50 tags, and the module adds Name unless tags already sets it."
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
  description = "Terraform-side waits for create, update, and delete, as Go durations such as \"45m\" or \"1h30m\". Unset fields keep the provider defaults (30m each). Raise them for vendor stacks that take long to converge; this does not change CloudFormation's own timeout_in_minutes."
  type = object({
    create = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for value in [var.timeouts.create, var.timeouts.update, var.timeouts.delete] : value == null ? true : can(regex("^([0-9]+(\\.[0-9]+)?(h|m|s))+$", value))])
    error_message = "Each timeouts field must be a Go duration such as \"30m\", \"2h\", or \"1h30m\"."
  }
}
