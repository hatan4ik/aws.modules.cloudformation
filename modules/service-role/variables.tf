variable "name" {
  description = "Name of the CloudFormation service role: 1 to 64 characters of letters, digits, and _+=,.@-. Changing it replaces the role, and a stack keeps using the role it was created with, so rename only together with the stack."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", var.name))
    error_message = "name must be an IAM role name: 1 to 64 characters of letters, digits, and _+=,.@-."
  }
}

variable "path" {
  description = "IAM path of the role, \"/\" by default. A dedicated path such as \"/cloudformation/\" lets the deploying principal's iam:PassRole be scoped to arn:<partition>:iam::<account>:role/cloudformation/*, the pattern AWS's least-privilege guidance for CloudFormation shows."
  type        = string
  default     = "/"
  nullable    = false

  validation {
    condition     = length(var.path) <= 512 && can(regex("^/([A-Za-z0-9_+=,.@-]+/)*$", var.path))
    error_message = "path must start and end with / and contain only letters, digits, and _+=,.@- between slashes, at most 512 characters."
  }
}

variable "description" {
  description = "Description of the role, at most 1,000 characters of the set IAM accepts (printable ASCII, Latin-1, tab, and newlines). null (the default) uses one that names the role's purpose."
  type        = string
  default     = null

  validation {
    condition     = var.description == null ? true : length(var.description) <= 1000 && can(regex("^[\\t\\n\\r\\x{20}-\\x{7E}\\x{A1}-\\x{FF}]*$", var.description))
    error_message = "description must be at most 1,000 characters of printable ASCII, Latin-1 (U+00A1 to U+00FF), tab, and newlines (the IAM role description character set)."
  }
}

variable "account_id" {
  description = "12-digit ID of the account the role is created in, where the stacks that use it live. It scopes the trust policy's confused-deputy conditions (aws:SourceAccount, aws:SourceArn) to this account's CloudFormation; the module does no data-source reads, so it cannot look it up."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "statements" {
  description = <<-EOT
    The permissions the stack's template needs, as IAM policy statements keyed by Sid (1 to 100 letters and digits). The same shape aws.modules.ecs-service uses for role statements: effect (Allow by default, or Deny), actions, resources, and optional conditions ({ test, variable, values }).

    The module cannot infer these from a template. For each resource type the template declares, the registry schema's handlers section lists what CloudFormation calls to create, read, update, and delete it: aws cloudformation describe-type --type RESOURCE --type-name AWS::S3::Bucket --query Schema --output text. Grant what the template's properties use, on the ARNs the template's names produce. At least one statement is required.
  EOT
  type = map(object({
    effect    = optional(string, "Allow")
    actions   = set(string)
    resources = set(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = set(string)
    })), [])
  }))
  nullable = false

  validation {
    condition     = length(var.statements) > 0
    error_message = "statements needs at least one statement: a service role exists to grant what the template creates."
  }

  validation {
    condition = alltrue([for sid, statement in var.statements :
      can(regex("^[A-Za-z0-9]{1,100}$", sid)) &&
      contains(["Allow", "Deny"], statement.effect) &&
      length(statement.actions) > 0 && length(statement.resources) > 0 &&
      length(distinct([for condition in statement.conditions : "${condition.test}|${condition.variable}"])) == length(statement.conditions)
    ])
    error_message = "Each statement key must be an alphanumeric Sid (1 to 100 characters), effect must be Allow or Deny, actions and resources must be non-empty, and condition test/variable pairs must be unique."
  }

  validation {
    condition     = alltrue(flatten([for statement in values(var.statements) : [for action in statement.actions : can(regex("^(\\*|[a-z0-9-]+:[A-Za-z0-9*?]+)$", action))]]))
    error_message = "Each action must be \"<service>:<Action>\" (wildcards * and ? allowed in the action part), or \"*\"."
  }

  validation {
    condition     = alltrue(flatten([for statement in values(var.statements) : [for condition in statement.conditions : length(condition.values) > 0 && condition.test != "" && condition.variable != ""]]))
    error_message = "Each condition needs a test (such as StringEquals), a variable (such as aws:RequestTag/Team), and at least one value."
  }
}

variable "pass_roles" {
  description = <<-EOT
    iam:PassRole grants, for templates that hand a role to a service: a template that creates a Lambda function's execution role and then the function, or references an existing role, makes CloudFormation pass that role, which needs iam:PassRole on it. Keyed by Sid (1 to 100 letters and digits). role_arns lists the roles (a name may end in a wildcard, such as role/my-stack-*, for the generated names of roles the template creates); services lists the service principals the roles may be passed to, rendered as the iam:PassedToService condition AWS recommends (for example lambda.amazonaws.com). Both are required, so a grant can never be "any role to any service". Empty by default. Creating the roles themselves (iam:CreateRole and the rest) is an ordinary statement.
  EOT
  type = map(object({
    role_arns = set(string)
    services  = set(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for sid, grant in var.pass_roles :
      can(regex("^[A-Za-z0-9]{1,100}$", sid)) &&
      length(grant.role_arns) > 0 && length(grant.services) > 0
    ])
    error_message = "Each pass_roles key must be an alphanumeric Sid (1 to 100 characters), with at least one role ARN and one service."
  }

  validation {
    condition     = alltrue(flatten([for grant in values(var.pass_roles) : [for arn in grant.role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/*-]{1,512}$", arn))]]))
    error_message = "Each pass_roles role ARN must be arn:<partition>:iam::<12-digit account>:role/<path/name>, with * allowed only in the path and name."
  }

  validation {
    condition     = alltrue(flatten([for grant in values(var.pass_roles) : [for service in grant.services : can(regex("^[a-z0-9.-]+\\.amazonaws\\.com(\\.cn)?$", service))]]))
    error_message = "Each pass_roles service must be a service principal such as lambda.amazonaws.com, with no wildcard."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN of a managed policy set as the role's permissions boundary, which caps what the role can do whatever its statements say. null (the default) sets none."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary_arn == null ? true : can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/[A-Za-z0-9+=,.@_/-]{1,640}$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be an IAM managed policy ARN (arn:<partition>:iam::aws:policy/... or arn:<partition>:iam::<account>:policy/...)."
  }
}

variable "tags" {
  description = "Tags applied to the role. The module adds Name = name; a Name given here wins. At most 50 tags in total including Name (provider default_tags also count). Keys 1 to 128 and values 0 to 256 characters of letters, digits, spaces, and _ . : / = + - @; no aws: key prefix."
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
    # IAM Tag: key 1-128 and value 0-256 characters, as in
    # modules/self-managed-roles.
    condition = alltrue([
      for key, value in var.tags :
      length(key) >= 1 && length(key) <= 128 && can(regex("^[\\p{L}\\p{Z}\\p{N}_.:/=+\\-@]+$", key)) &&
      length(value) <= 256 && can(regex("^[\\p{L}\\p{Z}\\p{N}_.:/=+\\-@]*$", value))
    ])
    error_message = "Tag keys must be 1 to 128 characters and values 0 to 256, both of letters, digits, spaces, and _ . : / = + - @."
  }
}
