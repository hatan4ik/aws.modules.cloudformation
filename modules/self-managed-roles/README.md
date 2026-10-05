# self-managed-roles

Creates the two IAM roles a **self-managed** CloudFormation StackSet cannot work without, one per module call: the administration role in the administrator account (`role = { administration = {...} }`), or the execution role in a target account (`role = { execution = {...} }`). The administration call's `stack_set_permission_model` output is exactly what [`modules/stack-set`](../stack-set) takes as `permission_model`.

## Why this exists

A self-managed StackSet works only after two roles exist: `AWSCloudFormationStackSetAdministrationRole` in the account that owns the StackSet, and `AWSCloudFormationStackSetExecutionRole` in every account it deploys to, trusting the first. Under the self-managed model nothing in AWS creates them for you; AWS's own answer is two sample CloudFormation templates you deploy by hand in each account before your first StackSet. That is a chicken-and-egg problem for a Terraform platform: `modules/stack-set` takes the role ARN and name as inputs, and before this submodule nothing in this repository could produce them.

The roles here are the AWS samples translated to Terraform, with the same names, the same one-permission administration policy, and the same trust direction, and three deliberate tightenings (each documented by AWS, none of them granting anything the samples do not):

| | AWS sample template | This module |
| --- | --- | --- |
| Administration role trust | `cloudformation.amazonaws.com` | the same, plus the `aws:SourceAccount` and `aws:SourceArn` conditions AWS recommends against the confused-deputy problem, and regional principals for `opt_in_regions` |
| Administration role permission | `sts:AssumeRole` on `arn:*:iam::*:role/<execution role>` | the same; `target_account_ids` narrows `*` to listed accounts |
| Execution role trust | the whole administrator account (`arn:aws:iam::<admin>:root`) | only the administration role ARNs given (AWS's documented form for customized administration roles) |
| Execution role permissions | `AdministratorAccess`, which the AWS guide says to scope down afterwards | `cloudformation:*` only (the minimum AWS documents); you add what your template needs with `inline_policy` or `policy_arns` |

Sources: the sample templates [AWSCloudFormationStackSetAdministrationRole.yml](https://s3.amazonaws.com/cloudformation-stackset-sample-templates-us-east-1/AWSCloudFormationStackSetAdministrationRole.yml) and [AWSCloudFormationStackSetExecutionRole.yml](https://s3.amazonaws.com/cloudformation-stackset-sample-templates-us-east-1/AWSCloudFormationStackSetExecutionRole.yml), and the guide [Grant self-managed permissions](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-prereqs-self-managed.html).

## What it does not do

- **Organizations trusted access.** That is the `service_managed` model's prerequisite, where AWS creates the roles itself; see [`modules/stack-set` Prerequisites](../stack-set/README.md#prerequisites). This module is for `self_managed` only.
- **Reach into other accounts.** Each call creates one role in the account of the provider it runs with. Creating the execution role in a target account needs a provider for that account (an `assume_role` provider, as in [`examples/self-managed-bootstrap`](../../examples/self-managed-bootstrap)), or the target account's own Terraform root.
- **Decide what your StackSet may create.** The execution role's permissions beyond `cloudformation:*` are template-specific; the module takes them as input and attaches nothing broader by default.
- **Grant `iam:PassRole`.** Whoever runs Terraform to create or update the StackSet needs `iam:PassRole` on the administration role. That belongs to the deploying principal's own policy:

  ```json
  {
    "Effect": "Allow",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::111111111111:role/AWSCloudFormationStackSetAdministrationRole"
  }
  ```

## Usage

```hcl
# Administrator account (default provider).
module "stack_set_administration_role" {
  source = "git::https://github.com/hatan4ik/aws.modules.cloudformation.git//modules/self-managed-roles?ref=<commit-sha>" # vX.Y.Z

  role = {
    administration = {
      account_id         = "111111111111" # this account
      target_account_ids = ["222222222222"]
    }
  }
}

# Each target account (a provider with credentials there).
module "stack_set_execution_role" {
  source    = "git::https://github.com/hatan4ik/aws.modules.cloudformation.git//modules/self-managed-roles?ref=<commit-sha>" # vX.Y.Z
  providers = { aws = aws.target_222222222222 }

  role = {
    execution = {
      administration_role_arns = [module.stack_set_administration_role.role_arn]
      inline_policy            = data.aws_iam_policy_document.what_the_template_creates.json
    }
  }
}

module "baseline" {
  source = "git::https://github.com/hatan4ik/aws.modules.cloudformation.git//modules/stack-set?ref=<commit-sha>" # vX.Y.Z

  name             = "baseline"
  template         = { url = "https://baseline-templates.s3.us-east-1.amazonaws.com/baseline/v1.yaml" }
  permission_model = module.stack_set_administration_role.stack_set_permission_model
  stack_instances  = { "222222222222/us-east-1" = {} }

  depends_on = [module.stack_set_execution_role]
}
```

[`examples/self-managed-bootstrap`](../../examples/self-managed-bootstrap) is the complete, runnable version: zero to a deployed self-managed StackSet in one configuration.

## Behaviour

- One branch per call. `role` takes exactly one of `administration` or `execution`. An administrator account that also receives instances calls the module twice with the same provider.
- Names. Both default to the AWS standard names, which StackSets uses when no role is passed. The roles are created at path `/`: StackSets addresses the execution role by bare name (`arn:...:role/<name>`), so a path would make it unreachable. `execution_role_name` in the administration branch, `name` in the execution branch, and the StackSet's `execution_role_name` must be the same string; `stack_set_permission_model` carries the administration branch's value to the StackSet so those two cannot differ.
- Order. IAM rejects a trust policy whose principal does not exist, so the administration role must be created before any execution role that trusts it. Passing `role_arn` from the administration call into the execution call gives Terraform that order. The StackSet's instances need the execution role, which nothing in `modules/stack-set`'s inputs refers to, so add `depends_on` on the execution role call (or create it in an earlier apply).
- Trust by role ARN. IAM stores a role principal by its unique ID. If the administration role is deleted and recreated, the execution role's trust policy no longer matches the new role (AWS's guide calls this out too), and every instance operation fails until the execution role is updated. Apply both calls together after any administration role replacement.
- Opt-in Regions. To deploy to a Region that is disabled by default (such as `ap-east-1`), list it in `opt_in_regions` so the administration role trusts `cloudformation.<region>.amazonaws.com`, and enable the Region in both the administrator and the target accounts.
- Tags. The module adds `Name = <role name>`; a caller's `Name` wins.

## Failure modes

| Symptom (StackSet operation result) | Cause | Fix |
| --- | --- | --- |
| `Account <id> should have '<execution role>' role with trust relationship to Role '<administration role>'` | Execution role missing in that account, a different name, or trusting a different (or recreated) administration role | Create or re-apply the execution role call for that account; check the three names match. |
| Same error on the very first apply only | IAM is eventually consistent; the new role was not yet assumable | Apply again: the failed instance is tainted and recreated. |
| `AccessDenied` creating a resource inside the instance stack | The execution role lacks a permission the template needs | Add it to `inline_policy` or `policy_arns`; then re-run the rollout (see [`modules/stack-set` Failure modes](../stack-set/README.md#failure-modes)). |
| `is not authorized to perform: iam:PassRole` at `CreateStackSet` | The deploying principal cannot pass the administration role | Grant `iam:PassRole` on it (above). |
| Assume-role failure in an opt-in Region only | Regional service principal not trusted, or Region not enabled in one of the accounts | Add the Region to `opt_in_regions`; enable it in both accounts. |

## Quotas

IAM role trust policies are at most 2,048 characters by default (adjustable to 8,192), which bounds `opt_in_regions` and `administration_role_arns`; a role takes 20 managed policies by default (adjustable to 25). The inline policies of one role share 10,240 characters, whitespace not counted, which `inline_policy` is validated against.

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
| [aws_iam_role.administration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.administration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.execution_cloudformation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.execution_template](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_role"></a> [role](#input\_role) | Which self-managed StackSets role this call creates, in the account of the provider it runs with. Set exactly one branch; call the module once per account (twice in an administrator account that is also a target).<br/><br/>administration: the role CloudFormation assumes in the administrator account, the one that owns the StackSet. account\_id (required) is that account's 12-digit ID, used in the trust policy's aws:SourceAccount and aws:SourceArn conditions. name defaults to AWSCloudFormationStackSetAdministrationRole. execution\_role\_name (default AWSCloudFormationStackSetExecutionRole) is the role it may assume in target accounts. target\_account\_ids limits which accounts it may assume that role in; null (the default) allows any account, as AWS's sample template does. opt\_in\_regions lists Regions disabled by default (such as ap-east-1) the StackSet deploys to, whose regional CloudFormation service principal the trust policy must also name.<br/><br/>execution: the role CloudFormation assumes in a target account to create the instance stack. administration\_role\_arns (required, at least one) are the administration roles it trusts. name defaults to AWSCloudFormationStackSetExecutionRole and must match the StackSet's execution\_role\_name. The role always gets cloudformation:* (the minimum AWS documents); policy\_arns (managed policy ARNs keyed by a static label of your choice, so an ARN may be unknown until apply) and inline\_policy (a JSON policy document) add what the StackSet's template needs. Nothing broader is attached by default. | <pre>object({<br/>    administration = optional(object({<br/>      account_id          = string<br/>      name                = optional(string, "AWSCloudFormationStackSetAdministrationRole")<br/>      execution_role_name = optional(string, "AWSCloudFormationStackSetExecutionRole")<br/>      target_account_ids  = optional(set(string))<br/>      opt_in_regions      = optional(set(string), [])<br/>    }))<br/>    execution = optional(object({<br/>      administration_role_arns = set(string)<br/>      name                     = optional(string, "AWSCloudFormationStackSetExecutionRole")<br/>      policy_arns              = optional(map(string), {})<br/>      inline_policy            = optional(string)<br/>    }))<br/>  })</pre> | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the role. The module adds Name = the role name; a Name given here wins. At most 50 tags in total including Name (provider default\_tags also count). Keys 1 to 128 and values 0 to 256 characters of letters, digits, spaces, and \_ . : / = + - @; no aws: key prefix. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the role this call created (administration or execution). |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the role this call created (administration or execution). |
| <a name="output_stack_set_permission_model"></a> [stack\_set\_permission\_model](#output\_stack\_set\_permission\_model) | For an administration call: the value to pass as modules/stack-set's permission\_model, { self\_managed = { administration\_role\_arn, execution\_role\_name } }. The execution\_role\_name is the one this administration role may assume, so it always matches the role's policy. null for an execution call. |
<!-- END_TF_DOCS -->
