# Template from S3

A stack created from a template object in Amazon S3, the way AWS Marketplace listings and most vendors deliver CloudFormation: `template = { url = ... }`. Templates delivered this way may be up to 1 MB, against 51,200 bytes inline.

It also shows the inputs a vendor template usually needs:

- `capabilities = ["CAPABILITY_NAMED_IAM"]`, because the template creates named IAM roles. The module acknowledges nothing by default.
- `on_failure = "DELETE"`, so a failed first create removes the stack rather than leaving it in `ROLLBACK_COMPLETE` (see the module README, [Failure modes](../../README.md#failure-modes)).
- `timeout_in_minutes` with Terraform `timeouts` slightly longer, so CloudFormation's own failure is what you see.
- An SNS topic for stack events.

Pin `template_url` to an object version with `?versionId=<id>`. A URL whose object can be overwritten makes the same plan deploy different templates over time, and Terraform cannot see that change; the module's `template_url_not_version_pinned` check warns about such a URL. See the module README, [Template immutability](../../README.md#template-immutability).

## Run

```sh
terraform init
terraform plan \
  -var 'template_url=https://vendor-templates.s3.us-east-1.amazonaws.com/solution/v2.4.1/main.yaml?versionId=3HL4kqtJlcpXroDTDmJ.rmSpXd3dIbrHY' \
  -var cloudformation_role_arn=arn:aws:iam::123456789012:role/cloudformation-marketplace-solution \
  -var 'parameters={"VpcId":"vpc-0123456789abcdef0"}'
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
| <a name="module_marketplace_solution"></a> [marketplace\_solution](#module\_marketplace\_solution) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cloudformation_role_arn"></a> [cloudformation\_role\_arn](#input\_cloudformation\_role\_arn) | ARN of an existing IAM role that trusts cloudformation.amazonaws.com and holds exactly the permissions the vendor template needs. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Stack name. | `string` | `"marketplace-solution-example"` | no |
| <a name="input_notification_topic_arn"></a> [notification\_topic\_arn](#input\_notification\_topic\_arn) | Optional ARN of an existing SNS topic that receives the stack's events. null sends none. | `string` | `null` | no |
| <a name="input_parameters"></a> [parameters](#input\_parameters) | Template parameters the vendor documents, as strings. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region the stack is created in. | `string` | `"us-east-1"` | no |
| <a name="input_template_url"></a> [template\_url](#input\_template\_url) | https:// URL of the vendor's template object in Amazon S3, pinned to an object version with ?versionId=<id>. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_stack_id"></a> [stack\_id](#output\_stack\_id) | ID (ARN) of the stack. |
| <a name="output_stack_outputs"></a> [stack\_outputs](#output\_stack\_outputs) | Everything the vendor template exports through its Outputs section. |
<!-- END_TF_DOCS -->
