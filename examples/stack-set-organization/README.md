# Organization-wide StackSet

The case StackSets exist for: one template deployed to every account in a set of AWS Organizations OUs, and to every account that joins them later, from a single Terraform call. It uses the `modules/stack-set` submodule with `service_managed` permissions, so AWS Organizations creates the deployment roles in the member accounts; nothing has to be bootstrapped account by account.

The template, [`baseline.yaml`](baseline.yaml), creates one read-only audit role trusted by a security tooling account. Run this from the management account (`call_as = "SELF"`) or, preferably, from an account registered as a StackSets delegated administrator (`call_as = "DELEGATED_ADMIN"`, the default here).

What to look at:

- `stack_instances` is keyed `"<ou_id>/<region>"`. Each key is one `aws_cloudformation_stack_set_instance` that deploys to every account in the OU in that region.
- `operation_preferences` bounds the blast radius of a bad template: at most two accounts in flight, and the operation stops in a region, and skips the remaining regions, once more than one account has failed. A template update to this StackSet rolls out under the same rules. See the submodule README, [Failure modes](../../modules/stack-set/README.md#failure-modes).
- Every template parameter is declared, including `RoleName`, which has a `Default` in the template.

Prerequisites: an organization with all features enabled, trusted access for StackSets activated (`aws cloudformation activate-organizations-access`, which no Terraform resource does), and, for `DELEGATED_ADMIN`, the account registered as a delegated administrator. The ordered steps, with commands, are in the submodule README, [Prerequisites](../../modules/stack-set/README.md#prerequisites).

## Run

```sh
terraform init
terraform plan \
  -var security_account_id=111111111111 \
  -var 'organizational_unit_ids=["ou-ab12-11111111","ou-ab12-22222222"]'
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_audit_role_baseline"></a> [audit\_role\_baseline](#module\_audit\_role\_baseline) | ../../modules/stack-set | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_call_as"></a> [call\_as](#input\_call\_as) | SELF when running in the organization's management account, DELEGATED\_ADMIN when running in a registered StackSets delegated administrator account. | `string` | `"DELEGATED_ADMIN"` | no |
| <a name="input_name"></a> [name](#input\_name) | StackSet name. | `string` | `"security-audit-role-baseline"` | no |
| <a name="input_organizational_unit_ids"></a> [organizational\_unit\_ids](#input\_organizational\_unit\_ids) | IDs of the OUs (ou-xxxx-yyyyyyyy), or the organization root ID (r-xxxx), whose accounts get the role. | `set(string)` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region of the StackSet itself, and the one region its instances deploy to. | `string` | `"us-east-1"` | no |
| <a name="input_security_account_id"></a> [security\_account\_id](#input\_security\_account\_id) | 12-digit ID of the security tooling account the audit role trusts. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_stack_instances"></a> [stack\_instances](#output\_stack\_instances) | Per OU and region: the accounts the deployment reached and the stack each one runs. |
| <a name="output_stack_set_arn"></a> [stack\_set\_arn](#output\_stack\_set\_arn) | ARN of the StackSet. |
<!-- END_TF_DOCS -->
