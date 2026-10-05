variable "role" {
  description = <<-EOT
    Which self-managed StackSets role this call creates, in the account of the provider it runs with. Set exactly one branch; call the module once per account (twice in an administrator account that is also a target).

    administration: the role CloudFormation assumes in the administrator account, the one that owns the StackSet. account_id (required) is that account's 12-digit ID, used in the trust policy's aws:SourceAccount and aws:SourceArn conditions. name defaults to AWSCloudFormationStackSetAdministrationRole. execution_role_name (default AWSCloudFormationStackSetExecutionRole) is the role it may assume in target accounts. target_account_ids limits which accounts it may assume that role in; null (the default) allows any account, as AWS's sample template does. opt_in_regions lists Regions disabled by default (such as ap-east-1) the StackSet deploys to, whose regional CloudFormation service principal the trust policy must also name.

    execution: the role CloudFormation assumes in a target account to create the instance stack. administration_role_arns (required, at least one) are the administration roles it trusts. name defaults to AWSCloudFormationStackSetExecutionRole and must match the StackSet's execution_role_name. The role always gets cloudformation:* (the minimum AWS documents); policy_arns (managed policy ARNs keyed by a static label of your choice, so an ARN may be unknown until apply) and inline_policy (a JSON policy document) add what the StackSet's template needs. Nothing broader is attached by default.
  EOT
  type = object({
    administration = optional(object({
      account_id          = string
      name                = optional(string, "AWSCloudFormationStackSetAdministrationRole")
      execution_role_name = optional(string, "AWSCloudFormationStackSetExecutionRole")
      target_account_ids  = optional(set(string))
      opt_in_regions      = optional(set(string), [])
    }))
    execution = optional(object({
      administration_role_arns = set(string)
      name                     = optional(string, "AWSCloudFormationStackSetExecutionRole")
      policy_arns              = optional(map(string), {})
      inline_policy            = optional(string)
    }))
  })
  nullable = false

  validation {
    condition     = (var.role.administration == null) != (var.role.execution == null)
    error_message = "role needs exactly one of administration or execution. Call the module once per account; an administrator account that is also a target calls it twice."
  }

  validation {
    condition     = var.role.administration == null ? true : can(regex("^[0-9]{12}$", var.role.administration.account_id))
    error_message = "role.administration.account_id must be a 12-digit AWS account ID."
  }

  validation {
    condition = var.role.administration == null ? true : (
      can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", var.role.administration.name)) &&
      can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", var.role.administration.execution_role_name))
    )
    error_message = "role.administration.name and execution_role_name must be IAM role names: 1 to 64 characters of letters, digits, and _+=,.@- (no path)."
  }

  validation {
    condition = try(var.role.administration.target_account_ids, null) == null ? true : (
      length(var.role.administration.target_account_ids) > 0 &&
      alltrue([for id in var.role.administration.target_account_ids : can(regex("^[0-9]{12}$", id))])
    )
    error_message = "role.administration.target_account_ids must be null (any account) or a non-empty set of 12-digit account IDs."
  }

  validation {
    condition     = var.role.administration == null ? true : alltrue([for region in var.role.administration.opt_in_regions : can(regex("^[a-z]{2}-(gov-|iso-|isob-)?[a-z]+-[0-9]$", region))])
    error_message = "role.administration.opt_in_regions must contain AWS Region codes such as ap-east-1."
  }

  validation {
    condition = var.role.execution == null ? true : (
      length(var.role.execution.administration_role_arns) > 0 &&
      alltrue([for arn in var.role.execution.administration_role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]{1,512}$", arn))])
    )
    error_message = "role.execution.administration_role_arns must hold at least one IAM role ARN (arn:<partition>:iam::<account>:role/<path/name>)."
  }

  validation {
    condition     = var.role.execution == null ? true : can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", var.role.execution.name))
    error_message = "role.execution.name must be an IAM role name: 1 to 64 characters of letters, digits, and _+=,.@- (no path; StackSets builds the role ARN from the bare name)."
  }

  validation {
    condition     = var.role.execution == null ? true : alltrue([for arn in values(var.role.execution.policy_arns) : can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/[A-Za-z0-9+=,.@_/-]{1,640}$", arn))])
    error_message = "role.execution.policy_arns must contain IAM managed policy ARNs (arn:<partition>:iam::aws:policy/... or arn:<partition>:iam::<account>:policy/...)."
  }

  validation {
    # IAM counts the aggregate size of a role's inline policies without
    # whitespace, at most 10,240 characters. The module's own cloudformation:*
    # policy takes 100 of them, so the caller's document may use 10,140.
    condition = try(var.role.execution.inline_policy, null) == null ? true : (
      can(jsondecode(var.role.execution.inline_policy).Statement) &&
      length(replace(var.role.execution.inline_policy, "/\\s/", "")) <= 10140
    )
    error_message = "role.execution.inline_policy must be a JSON IAM policy document with a Statement, at most 10,140 characters without whitespace (the 10,240-character inline policy quota per role, minus the module's own cloudformation:* policy)."
  }
}

variable "tags" {
  description = "Tags applied to the role. The module adds Name = the role name; a Name given here wins. At most 50 tags in total including Name (provider default_tags also count). Keys 1 to 128 and values 0 to 256 characters of letters, digits, spaces, and _ . : / = + - @; no aws: key prefix."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = length(merge({ Name = "" }, var.tags)) <= 50
    error_message = "An IAM role takes at most 50 tags, and the module adds Name unless tags already sets it."
  }

  validation {
    condition     = alltrue([for key in keys(var.tags) : !startswith(lower(key), "aws:")])
    error_message = "Tag keys may not start with the reserved aws: prefix."
  }

  validation {
    # IAM Tag: key 1-128 and value 0-256 characters; unlike CloudFormation, IAM
    # accepts an empty value.
    condition = alltrue([
      for key, value in var.tags :
      length(key) >= 1 && length(key) <= 128 && can(regex("^[\\p{L}\\p{Z}\\p{N}_.:/=+\\-@]+$", key)) &&
      length(value) <= 256 && can(regex("^[\\p{L}\\p{Z}\\p{N}_.:/=+\\-@]*$", value))
    ])
    error_message = "Tag keys must be 1 to 128 characters and values 0 to 256, both of letters, digits, spaces, and _ . : / = + - @."
  }
}
