# Inline template

A stack whose template ships with the configuration: `template = { body = file(...) }` reads [`vendor-agent.yaml`](vendor-agent.yaml), a stand-in for a vendor-delivered template you have vendored into the repository at a pinned version. The example shows the shape the module expects a real use to have:

- every template parameter declared in `parameters`, as strings, including ones with a template `Default`;
- a CloudFormation service role (`iam_role_arn`), so the stack's permissions do not depend on who runs Terraform;
- an SNS topic for stack events, so a failed create or update is seen by someone;
- a stack policy that allows in-place modification but denies replacement and deletion of the stack's resources;
- the stack's own `Outputs` consumed downstream through `module.vendor_agent.outputs["..."]`.

The template creates a CloudWatch Logs log group. That is deliberately trivial: in a real configuration a log group is an `aws_cloudwatch_log_group`, and this module is for templates you receive, not ones you write. See the module's [Why this module exists](../../docs/DESIGN.md#why-this-module-exists).

## Run

```sh
terraform init
terraform plan \
  -var cloudformation_role_arn=arn:aws:iam::123456789012:role/cloudformation-vendor-agent \
  -var notification_topic_arn=arn:aws:sns:us-east-1:123456789012:stack-events
```

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
| <a name="module_vendor_agent"></a> [vendor\_agent](#module\_vendor\_agent) | ../../ | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_subscription_filter.forward](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_subscription_filter) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cloudformation_role_arn"></a> [cloudformation\_role\_arn](#input\_cloudformation\_role\_arn) | ARN of an existing IAM role that trusts cloudformation.amazonaws.com and may manage CloudWatch Logs log groups. CloudFormation assumes it for every operation on the stack. | `string` | n/a | yes |
| <a name="input_destination_arn"></a> [destination\_arn](#input\_destination\_arn) | Optional ARN of an existing log destination (Kinesis stream, Firehose, or Lambda) to forward the agent's logs to. null skips the subscription. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Stack name; also passed to the template as AgentName. | `string` | `"vendor-agent-example"` | no |
| <a name="input_notification_topic_arn"></a> [notification\_topic\_arn](#input\_notification\_topic\_arn) | ARN of an existing SNS topic that receives the stack's events. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region the stack is created in. | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_log_group_arn"></a> [log\_group\_arn](#output\_log\_group\_arn) | ARN of the log group the template created, read from the stack's Outputs. |
| <a name="output_stack_arn"></a> [stack\_arn](#output\_stack\_arn) | ARN of the stack. |
<!-- END_TF_DOCS -->
