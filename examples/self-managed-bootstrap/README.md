# Self-managed StackSet from zero

Everything a self-managed StackSet needs, in one configuration and one `terraform apply`: no AWS sample templates deployed by hand, no role ARN pasted in from somewhere else. Read top to bottom, [`main.tf`](main.tf) is the whole prerequisite chain:

1. **Administration role**, in the administrator account (the account Terraform's default provider runs in): [`modules/self-managed-roles`](../../modules/self-managed-roles) with `role = { administration = {...} }`. CloudFormation assumes it; it may only assume the execution role, only in the target account.
2. **Execution role**, in the target account, through a second provider that assumes `target_account_role_arn`: the same submodule with `role = { execution = {...} }`. It trusts exactly the role from step 1 and is allowed `cloudformation:*` plus the SSM actions [`parameter.yaml`](parameter.yaml) needs, on `/stackset-bootstrap/*` parameters only.
3. **The StackSet**, in the administrator account: [`modules/stack-set`](../../modules/stack-set) with `permission_model = module.stack_set_administration_role.stack_set_permission_model`, which carries the administration role ARN and execution role name from step 1, and one instance in the target account.

For more target accounts, add a provider and an execution role call per account (or create the execution role from each account's own Terraform root), list the accounts in `target_account_ids`, and add one `stack_instances` key per account and region.

## Before you run it

- Credentials for the **administrator account** with permission to create IAM roles, to create a StackSet, and `iam:PassRole` on the administration role (`arn:aws:iam::<admin>:role/AWSCloudFormationStackSetAdministrationRole`).
- A role in the **target account** that those credentials may assume, with permission to create an IAM role and its inline policy. In an AWS Organization this is often `OrganizationAccountAccessRole`; otherwise your landing zone's deployment role.
- Nothing in AWS Organizations: the self-managed model works across any accounts, in an organization or not. (Service-managed StackSets have a different chain; see [`modules/stack-set`, Prerequisites](../../modules/stack-set/README.md#prerequisites).)

## Run

```sh
terraform init
terraform apply \
  -var target_account_id=222222222222 \
  -var target_account_role_arn=arn:aws:iam::222222222222:role/OrganizationAccountAccessRole

aws ssm get-parameter --name /stackset-bootstrap/message   # with target account credentials
terraform destroy \
  -var target_account_id=222222222222 \
  -var target_account_role_arn=arn:aws:iam::222222222222:role/OrganizationAccountAccessRole
```

Everything it creates is free: two IAM roles, a StackSet, and one standard-tier SSM parameter. `terraform destroy` deletes the instance stack (and the parameter) before the roles, because the StackSet depends on them.

What to expect:

- The first apply can fail on the instance with `Account 222222222222 should have 'AWSCloudFormationStackSetExecutionRole' role with trust relationship to Role 'AWSCloudFormationStackSetAdministrationRole'` even though both roles exist: IAM is eventually consistent and the brand-new roles may not be assumable yet. Apply again; the failed instance is tainted and recreated.
- If you replace the administration role later, re-apply the execution role too: its trust policy pins the old role.

The configuration has a credential-free test (`terraform test`, both providers mocked) that applies all three calls and checks they are wired to each other.

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

| Name | Source | Version |
|------|--------|---------|
| <a name="module_parameter_baseline"></a> [parameter\_baseline](#module\_parameter\_baseline) | ../../modules/stack-set | n/a |
| <a name="module_stack_set_administration_role"></a> [stack\_set\_administration\_role](#module\_stack\_set\_administration\_role) | ../../modules/self-managed-roles | n/a |
| <a name="module_stack_set_execution_role"></a> [stack\_set\_execution\_role](#module\_stack\_set\_execution\_role) | ../../modules/self-managed-roles | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_caller_identity.administrator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | StackSet name. | `string` | `"self-managed-bootstrap"` | no |
| <a name="input_region"></a> [region](#input\_region) | Region of the StackSet, and the one region its instance deploys to. | `string` | `"us-east-1"` | no |
| <a name="input_target_account_id"></a> [target\_account\_id](#input\_target\_account\_id) | 12-digit ID of the target account the StackSet deploys to. | `string` | n/a | yes |
| <a name="input_target_account_role_arn"></a> [target\_account\_role\_arn](#input\_target\_account\_role\_arn) | ARN of a role in the target account that Terraform assumes to create the execution role there (for example OrganizationAccountAccessRole, or your landing zone's deployment role). It needs IAM permissions to create a role and its policies. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_administration_role_arn"></a> [administration\_role\_arn](#output\_administration\_role\_arn) | ARN of the StackSets administration role in the administrator account. |
| <a name="output_execution_role_arn"></a> [execution\_role\_arn](#output\_execution\_role\_arn) | ARN of the StackSets execution role in the target account. |
| <a name="output_stack_instances"></a> [stack\_instances](#output\_stack\_instances) | The instance in the target account and region, with its stack ID. |
| <a name="output_stack_set_arn"></a> [stack\_set\_arn](#output\_stack\_set\_arn) | ARN of the StackSet. |
<!-- END_TF_DOCS -->
