# Stack with a scoped service role

The intended narrow path, end to end: a stack whose CloudFormation service role can create, update, read, and delete exactly the two resources its template declares, and nothing else. [`main.tf`](main.tf) has two steps:

1. **The service role**, [`modules/service-role`](../../modules/service-role): trusted only by CloudFormation, at path `/cloudformation/`, with two statements, one per resource in [`artifacts.yaml`](artifacts.yaml).
2. **The stack**, the root module, with `iam_role_arn = module.cloudformation_role.role_arn`. That output depends on the role's policies, so the stack waits for its permissions on create and is deleted before they are removed.

How the statements were written, which is the part no module can do for you:

- **Actions** come from each resource type's registry schema (`aws cloudformation describe-type --type RESOURCE --type-name AWS::S3::Bucket --query Schema --output text`, then its `handlers`). For `AWS::SSM::Parameter` that is the whole list. For `AWS::S3::Bucket` the create and update handlers list every optional bucket feature; the role takes only those for the properties the template sets (encryption, public access block, versioning, tags), plus the read handler's full list, because CloudFormation reads the whole bucket configuration back after each operation.
- **Resources** come from the names the template gives: the bucket is `<stack name>-<account>-<region>` and the parameter lives under `/<stack name>/`, so the role is scoped to them before the stack exists.

The credential-free test in [`tests/wiring.tftest.hcl`](tests/wiring.tftest.hcl) applies the example against a mocked provider and asserts the scoping itself: the template declares exactly the two resource types, the role grants actions of exactly their two services, on exactly the two resources, with no `*` action or resource and no `iam:PassRole`.

## Before you run it

- Credentials with permission to create an IAM role and its inline policy, to create a stack, and `iam:PassRole` on `arn:aws:iam::<account>:role/cloudformation/*`.
- An SNS topic for the stack's events (`notification_topic_arn`).
- The stack name (`name`) at most 40 characters, so the bucket name fits S3's 63.

## Run

```sh
terraform init
terraform apply -var notification_topic_arn=arn:aws:sns:us-east-1:123456789012:stack-events
terraform output bucket_name
terraform destroy -var notification_topic_arn=arn:aws:sns:us-east-1:123456789012:stack-events
```

If the template grows a resource, add its statement in the same change; until then, the stack's create or update fails with `AccessDenied` in its events, which is the role doing its job.

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
| <a name="module_artifacts"></a> [artifacts](#module\_artifacts) | ../../ | n/a |
| <a name="module_cloudformation_role"></a> [cloudformation\_role](#module\_cloudformation\_role) | ../../modules/service-role | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Stack name. It also prefixes the bucket name and the SSM parameter path, which is how the service role's statements are scoped to this stack's resources; keep it at most 40 characters so the bucket name fits S3's 63. | `string` | `"scoped-service-role"` | no |
| <a name="input_notification_topic_arn"></a> [notification\_topic\_arn](#input\_notification\_topic\_arn) | ARN of an existing SNS topic that receives the stack's events. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region the stack and its resources are created in. | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Name of the bucket the stack created, from its BucketName output. |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the scoped CloudFormation service role. |
| <a name="output_stack_id"></a> [stack\_id](#output\_stack\_id) | ID (ARN) of the stack. |
<!-- END_TF_DOCS -->
