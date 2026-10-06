# service-role

Creates one CloudFormation **stack service role** per call: the role the root module's `iam_role_arn` names, trusted only by `cloudformation.amazonaws.com`, carrying exactly the IAM statements you give it. Its `role_arn` output plugs straight into the root module's `iam_role_arn`.

## Why this exists

The root module takes `iam_role_arn` as an input, and that is correct: what a stack's role may do is whatever its template creates, which only the template's owner knows. But with nothing to help, the path of least resistance when a stack will not apply is to attach `AdministratorAccess` to a role and move on. That role then works for every stack that uses it, and for anyone allowed to update such a stack, whether or not they could pass it themselves.

This module makes the narrow role as quick to write as the wide one. You still list the permissions (that part is unavoidable, and is the point); the module supplies everything else: a trust policy that only CloudFormation can use, with confused-deputy conditions; a stable, sorted policy document; scoped `iam:PassRole` for templates that hand roles to services; an optional permissions boundary; and an output whose dependencies make the stack wait for the policies and outlive none of them.

## What it does not do

- **Infer permissions from a template.** The module does not read the template. For each resource type the template declares, the registry schema's `handlers` section lists the actions CloudFormation calls to create, read, update, and delete it: `aws cloudformation describe-type --type RESOURCE --type-name AWS::S3::Bucket --query Schema --output text`. Grant what the template's properties use, on the ARNs its names produce.
- **Attach managed policies.** There is no `policy_arns` input, deliberately: it would make `AdministratorAccess` a one-line choice again. If a managed policy is really what the template needs, attach it to `role_name` outside the module, where it is visible in review.
- **Serve `modules/stack-set`.** A StackSet has no stack service role. Its self-managed model takes an administration role (which may only assume execution roles) and execution roles in target accounts; those are [`modules/self-managed-roles`](../self-managed-roles).
- **Grant `iam:PassRole` on this role.** Whoever runs Terraform needs `iam:PassRole` on the service role to create a stack with it. That belongs to the deploying principal's own policy; a dedicated `path` such as `/cloudformation/` lets it be scoped to `arn:aws:iam::<account>:role/cloudformation/*`.

## Usage

```hcl
module "cloudformation_role" {
  source = "git::https://github.com/hatan4ik/aws.modules.cloudformation.git//modules/service-role?ref=<commit-sha>" # vX.Y.Z

  name       = "cloudformation-vendor-agent"
  path       = "/cloudformation/"
  account_id = "123456789012"

  statements = {
    AgentLogGroup = {
      actions = [
        "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
        "logs:TagResource", "logs:UntagResource", "logs:ListTagsForResource",
      ]
      resources = ["arn:aws:logs:us-east-1:123456789012:log-group:/vendor/*"]
    }
    DescribeLogGroups = {
      actions   = ["logs:DescribeLogGroups"]
      resources = ["*"] # not resource-scoped
    }
  }
}

module "vendor_agent" {
  source = "git::https://github.com/hatan4ik/aws.modules.cloudformation.git?ref=<commit-sha>" # vX.Y.Z

  name         = "vendor-agent"
  template     = { body = file("${path.module}/vendor-agent.yaml") }
  iam_role_arn = module.cloudformation_role.role_arn
}
```

A template that creates a Lambda function and its execution role needs `iam:CreateRole` and friends in `statements` (scope them with an `iam:PermissionsBoundary` condition if your account requires boundaries on new roles), plus a pass-role grant so CloudFormation can hand the new role to Lambda:

```hcl
  pass_roles = {
    FunctionRole = {
      role_arns = ["arn:aws:iam::123456789012:role/vendor-agent-*"] # the template's generated role names
      services  = ["lambda.amazonaws.com"]                          # rendered as iam:PassedToService
    }
  }
```

[`examples/scoped-service-role`](../../examples/scoped-service-role) is a complete, runnable version: a template with an S3 bucket and an SSM parameter, and a role scoped to exactly those two resources.

## Behaviour

- Trust. Only `cloudformation.amazonaws.com` may assume the role, under `StringEqualsIfExists` `aws:SourceAccount` = `account_id` and `ArnLikeIfExists` `aws:SourceArn` = `arn:*:cloudformation:*:<account_id>:*`. This is `modules/self-managed-roles`' confused-deputy pattern with the `IfExists` operators: AWS documents these condition keys for StackSets, registry, and Git sync roles, but not for a stack service role, so the conditions bind whenever CloudFormation supplies the keys and never make the role unassumable when it does not. See [docs/DESIGN.md, D15](../../docs/DESIGN.md#d15-a-stack-service-role-factory-not-a-permission-inferrer).
- Statements. `statements` is keyed by Sid, the shape `aws.modules.ecs-service` uses for role statements: `effect` (default `Allow`), `actions`, `resources`, and `conditions` (`{ test, variable, values }`). They render as one inline policy, `CloudFormationTemplate`, in Sid order with sorted lists, so the plan diff is stable. `Deny` statements are allowed and are a good way to fence the role (for example a `Deny` of `*` outside one Region).
- Pass role. Each `pass_roles` entry is a separate statement in the inline policy `CloudFormationPassRole`: `iam:PassRole` on `role_arns`, only when `iam:PassedToService` is one of `services`. Both lists are required.
- Size. IAM limits a role's inline policies to 10,240 characters in total, not counting whitespace; a precondition fails the plan above that, with the measured size.
- Ordering. `role_arn` depends on the policies as well as the role, so a stack that uses it is created after its permissions exist and, on destroy, deleted before they are removed (CloudFormation uses the role for the delete too). Without that, a stack would depend on the role alone.
- Tags. The module adds `Name = name`; a caller's `Name` wins.

## Failure modes

| What happened | What you see | What to do |
| --- | --- | --- |
| A statement is missing an action the template needs | The stack's first create fails with `AccessDenied` in its events, and the stack is left in `ROLLBACK_COMPLETE` (see the root README, Failure modes) | Add the action named in the event, apply: the tainted stack is replaced. |
| IAM has not yet propagated a just-attached policy | Rarely, the first create fails with `AccessDenied` although the action is granted | Apply again. |
| The role is deleted while a stack still uses it | Every later stack operation, including delete, fails: the role cannot be assumed | Recreate the role with the same name (or `aws cloudformation delete-stack --role-arn` another role). |
| `check.statement_allows_every_action` warns | A statement allows `*` | List the template's actions instead. |
| `check.pass_role_to_any_role` warns | A pass-role grant names `role/*` | Name the roles, or a prefix. |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.pass_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.template](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | 12-digit ID of the account the role is created in, where the stacks that use it live. It scopes the trust policy's confused-deputy conditions (aws:SourceAccount, aws:SourceArn) to this account's CloudFormation; the module does no data-source reads, so it cannot look it up. | `string` | n/a | yes |
| <a name="input_description"></a> [description](#input\_description) | Description of the role, at most 1,000 characters of the set IAM accepts (printable ASCII, Latin-1, tab, and newlines). null (the default) uses one that names the role's purpose. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the CloudFormation service role: 1 to 64 characters of letters, digits, and \_+=,.@-. Changing it replaces the role, and a stack keeps using the role it was created with, so rename only together with the stack. | `string` | n/a | yes |
| <a name="input_pass_roles"></a> [pass\_roles](#input\_pass\_roles) | iam:PassRole grants, for templates that hand a role to a service: a template that creates a Lambda function's execution role and then the function, or references an existing role, makes CloudFormation pass that role, which needs iam:PassRole on it. Keyed by Sid (1 to 100 letters and digits). role\_arns lists the roles (a name may end in a wildcard, such as role/my-stack-*, for the generated names of roles the template creates); services lists the service principals the roles may be passed to, rendered as the iam:PassedToService condition AWS recommends (for example lambda.amazonaws.com). Both are required, so a grant can never be "any role to any service". Empty by default. Creating the roles themselves (iam:CreateRole and the rest) is an ordinary statement. | <pre>map(object({<br/>    role_arns = set(string)<br/>    services  = set(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_path"></a> [path](#input\_path) | IAM path of the role, "/" by default. A dedicated path such as "/cloudformation/" lets the deploying principal's iam:PassRole be scoped to arn:<partition>:iam::<account>:role/cloudformation/*, the pattern AWS's least-privilege guidance for CloudFormation shows. | `string` | `"/"` | no |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | ARN of a managed policy set as the role's permissions boundary, which caps what the role can do whatever its statements say. null (the default) sets none. | `string` | `null` | no |
| <a name="input_statements"></a> [statements](#input\_statements) | The permissions the stack's template needs, as IAM policy statements keyed by Sid (1 to 100 letters and digits). The same shape aws.modules.ecs-service uses for role statements: effect (Allow by default, or Deny), actions, resources, and optional conditions ({ test, variable, values }).<br/><br/>The module cannot infer these from a template. For each resource type the template declares, the registry schema's handlers section lists what CloudFormation calls to create, read, update, and delete it: aws cloudformation describe-type --type RESOURCE --type-name AWS::S3::Bucket --query Schema --output text. Grant what the template's properties use, on the ARNs the template's names produce. At least one statement is required. | <pre>map(object({<br/>    effect    = optional(string, "Allow")<br/>    actions   = set(string)<br/>    resources = set(string)<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the role. The module adds Name = name; a Name given here wins. At most 50 tags in total including Name (provider default\_tags also count). Keys 1 to 128 and values 0 to 256 characters of letters, digits, spaces, and \_ . : / = + - @; no aws: key prefix. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_inline_policies"></a> [inline\_policies](#output\_inline\_policies) | The role's inline policy documents as JSON, keyed by policy name: CloudFormationTemplate (the statements) and, when pass\_roles is set, CloudFormationPassRole. For review, or for checking with IAM Access Analyzer's policy validation. |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the service role, for the root module's iam\_role\_arn. It depends on the role's policies as well as the role, so a stack that uses it is created after its permissions exist and destroyed before they are removed. |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the service role, for attaching further policies outside the module. |
<!-- END_TF_DOCS -->
