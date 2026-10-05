# aws.modules.cloudformation

Provisions one AWS CloudFormation stack per module call (`aws_cloudformation_stack`), and, through the [`modules/stack-set`](modules/stack-set) submodule, one CloudFormation StackSet with its stack instances across accounts and regions. Every rule CloudFormation enforces on the inputs that can be checked client-side fails at plan time: the template body-or-URL choice, the stack policy body-or-URL choice, the capability names, the stack name format, and the size and count limits. It creates nothing but the stack, performs no data-source reads, and requires Terraform >= 1.7 and the AWS provider >= 6.35, < 7.

**This platform is Terraform-first. This module is a narrow escape hatch, not a default.** Use it when a team must provision something that only ships as a CloudFormation template (an AWS Marketplace or Serverless Application Repository solution, a vendor deliverable) or needs StackSets' multi-account, multi-region orchestration. Using it for anything Terraform can express natively is a smell. The reasoning is in [docs/DESIGN.md, Why this module exists](docs/DESIGN.md#why-this-module-exists).

## Why this module

What you get over a bare `aws_cloudformation_stack`:

- The template source as a real choice. `template = { body = ... }` or `template = { url = ... }`: exactly one, checked at plan. Same for `stack_policy`. A bare resource accepts both or neither and fails at apply.
- Limits checked in the right unit. The 51,200-byte inline template limit and the 16,384-byte stack policy limit are measured in UTF-8 bytes, not characters, so a template with non-ASCII text cannot pass plan and fail at apply. Parameter count (200), value size, tag count (50, including the module's `Name`), and notification topic count (5) are checked too.
- Capabilities acknowledged by name. `capabilities` accepts only `CAPABILITY_IAM`, `CAPABILITY_NAMED_IAM`, and `CAPABILITY_AUTO_EXPAND`, and is empty by default, so a template that creates IAM resources is a reviewed decision.
- An explicit service role. `iam_role_arn` makes CloudFormation operate the stack with a role you can audit instead of the credentials of whoever runs Terraform; an advisory check warns while it is unset.
- The stack's own `Outputs` as a map (`outputs`), which is the main reason to compose around a stack from Terraform.
- Only a `Name` tag is added, and a caller's `Name` wins (`merge({ Name = name }, tags)`).
- A documented failure model: what `ROLLBACK_COMPLETE` means, how Terraform recovers from it, and the cases where an operator has to step in ([Failure modes](#failure-modes)).

## Quick start

```hcl
module "vendor_agent" {
  source = "git::https://github.com/hatan4ik/aws.modules.cloudformation.git?ref=<commit-sha>" # v1.0.0

  name     = "vendor-agent"
  template = { url = "https://vendor-templates.s3.us-east-1.amazonaws.com/agent/v4.2.0/agent.yaml" }

  parameters = {
    AgentName     = "vendor-agent"
    InstanceCount = "2" # parameters are always strings
  }
  capabilities = ["CAPABILITY_NAMED_IAM"]
  iam_role_arn = "arn:aws:iam::123456789012:role/cloudformation-vendor-agent"

  tags = { Environment = "prod", Owner = "platform" }
}

resource "aws_ssm_parameter" "agent_queue" {
  name  = "/vendor-agent/queue-url"
  type  = "String"
  value = module.vendor_agent.outputs["QueueUrl"]
}
```

This creates the stack `vendor-agent` from a versioned template object in S3, acknowledges that the template creates named IAM roles, lets CloudFormation operate the stack through the given service role, rolls the stack back if the first create fails, and exposes the stack's `QueueUrl` output to the rest of the configuration.

For StackSets, see [`modules/stack-set`](modules/stack-set) and [`examples/stack-set-organization`](examples/stack-set-organization).

## Architecture

```text
root (one stack)
├── stack.tf       aws_cloudformation_stack.this
├── variables.tf   every input, with the XOR and limit validations
├── locals.tf      tags (Name, then caller tags)
├── checks.tf      service_role_not_set (advisory)
└── outputs.tf     id, arn, name, outputs

modules/stack-set (one StackSet, N instances)
├── main.tf        aws_cloudformation_stack_set.this; aws_cloudformation_stack_set_instance.this["<target>/<region>"]
├── locals.tf      permission model, key splitting, operation preference split
├── checks.tf      no_stack_instances, max_concurrency_capped_by_failure_tolerance (advisory)
└── outputs.tf     id, arn, name, permission_model, stack_instances
```

The root module and the submodule are independent: the root never calls the submodule, and each can be used on its own.

| | Root module | `modules/stack-set` |
| --- | --- | --- |
| Resource | `aws_cloudformation_stack` | `aws_cloudformation_stack_set` + `aws_cloudformation_stack_set_instance` |
| Deploys to | the provider's account and region | any number of accounts (or OUs) and regions |
| Shared inputs | `name`, `template`, `parameters`, `capabilities`, `tags`, `timeouts` | the same, with the same rules |
| Own inputs | `on_failure`, `timeout_in_minutes`, `notification_arns`, `stack_policy`, `iam_role_arn` | `permission_model`, `stack_instances`, `operation_preferences`, `managed_execution_active`, `description` |
| Shared outputs | `id`, `arn`, `name` | `id`, `arn`, `name` |
| Own outputs | `outputs` (the stack's Outputs) | `permission_model`, `stack_instances` |

## Failure modes

The most important operational fact about a CloudFormation stack: **a stack whose first create fails and rolls back ends in `ROLLBACK_COMPLETE`, and CloudFormation never updates a stack in that state. It can only be deleted and created again.**

How this plays out with this module:

| What happened | State it leaves | What Terraform does | What you do |
| --- | --- | --- | --- |
| First create fails, `on_failure = "ROLLBACK"` (or unset, the default) | `ROLLBACK_COMPLETE` | The apply fails with the stack's failure events in the error. The provider recorded the stack ID before waiting, so the resource is in state as **tainted**. | Fix the cause (template, parameters, capabilities, role permissions). The next apply deletes the dead stack and creates a new one; the plan shows `must be replaced`. |
| First create fails, `on_failure = "DELETE"` | stack deleted (`DELETE_COMPLETE`) | The apply fails; the next refresh finds no stack and plans a create. | Fix the cause and apply. Events stay readable by stack ID for 90 days. |
| First create fails, `on_failure = "DO_NOTHING"` | `CREATE_FAILED`, partial resources kept | The apply fails and the resource is tainted. | Inspect the partial resources, then apply: the stack is replaced. |
| A stack in `ROLLBACK_COMPLETE` is **not** tainted (imported, `terraform untaint`, or state edited) | `ROLLBACK_COMPLETE` | The plan shows an in-place update, and the apply fails with `ValidationError: Stack ... is in ROLLBACK_COMPLETE state and can not be updated`. | `terraform apply -replace='module.<name>.aws_cloudformation_stack.this'`. |
| An update fails and rolls back | `UPDATE_ROLLBACK_COMPLETE` | The apply fails. The stack is healthy on the previous template and can be updated again. | Fix the cause and apply. |
| An update's rollback itself fails | `UPDATE_ROLLBACK_FAILED` | The apply fails, and every further update fails until the rollback completes. | `aws cloudformation continue-update-rollback --stack-name <name>`, adding `--resources-to-skip` for resources that cannot be rolled back, then apply. |
| Delete fails (for example a non-empty S3 bucket in the stack) | `DELETE_FAILED` | The destroy fails. | Empty or remove the blocking resource, then destroy again (or `aws cloudformation delete-stack --retain-resources ...`). |

**Detecting it.** The provider does not expose a stack's status as an attribute, so neither this module nor a `check` block can read it from the stack resource, and the module performs no data-source reads by design. Detect the state from outside Terraform:

```sh
aws cloudformation describe-stacks --stack-name <name> --query 'Stacks[0].[StackStatus,StackStatusReason]'
aws cloudformation describe-stack-events --stack-name <name> \
  --query 'StackEvents[?contains(ResourceStatus, `FAILED`)].[LogicalResourceId,ResourceStatusReason]'
terraform state show 'module.<name>.aws_cloudformation_stack.this'   # "(tainted)" after a failed create
```

Alarm on it with an EventBridge rule on `aws.cloudformation` `CloudFormation Stack Status Change` events whose `detail.status-details.status` is `ROLLBACK_COMPLETE`, `UPDATE_ROLLBACK_FAILED`, or `DELETE_FAILED`, or pass an SNS topic in `notification_arns`.

`on_failure` and `timeout_in_minutes` apply only to creation. Changing `timeout_in_minutes` on an existing stack replaces it. Changes to `on_failure` are ignored on an existing stack, because CloudFormation never returns it: editing it neither replaces the stack nor shows a diff, and it takes effect the next time the stack is created (including the replacement after a failed create). For the same reason, importing an existing stack plans no change for any `on_failure` value.

StackSets fail differently (per account and region, inside one operation); see [modules/stack-set, Failure modes](modules/stack-set/README.md#failure-modes).

## Security model

- Least privilege by role. With `iam_role_arn`, CloudFormation uses that role for every operation on the stack, and keeps using it even for callers who could not pass it themselves. Grant the role exactly what the template creates. Without it, the stack runs with whatever the Terraform caller can do, and `check.service_role_not_set` warns on every plan.
- No capability by default. A template that creates IAM resources or uses transforms fails with `InsufficientCapabilities` until the caller lists the capability. Review a template before acknowledging `CAPABILITY_NAMED_IAM` or `CAPABILITY_AUTO_EXPAND`: a transform runs a Lambda function that its owner can change without you.
- Parameters are not secret. `parameters` values are stored in plan and state in clear text, and the module does not mark them sensitive. `NoEcho` parameters read back from CloudFormation as `****`, which shows a diff on every plan. Resolve secrets inside the template with a dynamic reference (`{{resolve:secretsmanager:...}}` or `{{resolve:ssm-secure:...}}`) instead.
- Pin the template. A `template.url` whose object can be overwritten deploys whatever is there at apply time, and Terraform cannot see the change. Use a versioned key or a bucket with versioning and object lock.
- Stack policies are opt-in. `stack_policy` can deny `Update:Replace` and `Update:Delete` for stateful resources; with none, every resource in the stack can be replaced by an update.
- Tags propagate. CloudFormation copies stack tags, including `Name`, to every resource in the stack that supports tags.

## Lifecycle notes

- Parameters are strings on the wire: pass `"3"`, not `3`, and `"a,b"` for a `CommaDelimitedList`. Declare every parameter you care about; parameters you omit take the template `Default`.
- The provider normalises `template.body` (JSON and YAML), so reformatting a template does not show a diff, but any semantic change updates the stack in place.
- `outputs` is known only after apply. Downstream resources that read `outputs["Key"]` see an unknown value in the plan that creates the stack.
- Changing `name` or `timeout_in_minutes` replaces the stack (delete, then create), which destroys its resources unless the template sets `DeletionPolicy: Retain`.
- Terraform-side `timeouts` default to 30 minutes for create, update, and delete. Vendor stacks that create databases or clusters routinely need more.
- Termination protection is not supported by the provider's stack resource, and `prevent_destroy` cannot be added to a resource inside a module. Protect stateful resources with `DeletionPolicy: Retain` in the template (see [docs/DESIGN.md](docs/DESIGN.md#deferred-to-v2)).

## Testing

- Contract tests (`terraform test` in the root and in `modules/stack-set`, run by CI) use `mock_provider`: no credentials, nothing created. Plan-mode runs assert on every argument the module sends; every validation and precondition has a failing run through `expect_failures`; apply-mode runs in their own files give the stack ID, ARN, Outputs, and instance summaries realistic values with `override_resource` and prove every output resolves from the right attribute.
- Integration suite (`tests/integration/`, run by `make integration-smoke` or the dispatch-only `integration` workflow) applies the root module for real in **your** account: a stack with one `AWS::CloudFormation::WaitConditionHandle` (no billable resource) and two Outputs, asserts the stack ARN and Outputs the real API returns, and deletes it. See [tests/integration/README.md](tests/integration/README.md).

## Design principles

- Single responsibility. The root owns one stack; `modules/stack-set` owns one StackSet and its instances. Neither creates the service roles, templates, buckets, or topics it references.
- Open/closed. New stacks, parameters, and instances are data. Adding an account or region to a StackSet is one more `stack_instances` key.
- Liskov substitution. The submodule takes the same `name`, `template`, `parameters`, `capabilities`, `tags`, and `timeouts` with the same rules, and returns the same `id`, `arn`, and `name`, so moving from one stack to a StackSet does not mean relearning the interface. Where the resources differ (stack policies, StackSet operation preferences, per-instance outputs), the interfaces differ honestly instead of pretending.
- Interface segregation. A stack needs `name` and `template`; everything else is optional with the API's default or a safer one.
- Dependency inversion. Roles, topics, templates, OUs, and accounts are identifiers the caller passes in. No data sources.

The full rationale is in [docs/DESIGN.md](docs/DESIGN.md).

## Compatibility and scope

- Terraform `>= 1.7.0, < 2.0.0`. AWS provider `>= 6.35.0, < 7.0.0`.
- One stack in the provider's region. Change sets, drift detection, rollback triggers, termination protection, nested-stack management, stack imports, and Systems Manager document template URLs are out of scope for v1; see [docs/DESIGN.md, Deferred to v2](docs/DESIGN.md#deferred-to-v2).
- Quotas you can hit: 2,000 stacks per account and region (adjustable), 200 parameters and 200 outputs per template, 500 resources per template, a 51,200-byte inline template, and a 1 MB template object in S3.

## Versioning and releases

Releases follow semantic versioning: incompatible interface changes bump the major version, new optional inputs and outputs bump the minor version, fixes bump the patch version. Every release is a signed annotated tag `vX.Y.Z`.

Pin the full commit SHA of the release tag and record the tag in a comment, so the source cannot move under you:

```hcl
module "stack" {
  source = "git::https://github.com/hatan4ik/aws.modules.cloudformation.git?ref=<commit-sha>" # v1.0.0
}

module "stack_set" {
  source = "git::https://github.com/hatan4ik/aws.modules.cloudformation.git//modules/stack-set?ref=<commit-sha>" # v1.0.0
}
```

The `module-release` workflow publishes an immutable GitHub release only from a GitHub-verified, signed, annotated semantic-version tag that points at the merged `main` revision; lightweight or unsigned tags are rejected before anything is published. With a GitHub-associated GPG or SSH signing key configured:

```bash
git fetch origin
git tag -s vX.Y.Z <commit> -m "vX.Y.Z"
git push origin vX.Y.Z
gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z
```

All changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Contributing

Development setup, the local quality gate, the test-first workflow, and the release process are described in [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE).

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
| [aws_cloudformation_stack.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudformation_stack) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_capabilities"></a> [capabilities](#input\_capabilities) | Capabilities the template needs acknowledged: CAPABILITY\_IAM (creates IAM resources), CAPABILITY\_NAMED\_IAM (creates IAM resources with custom names), CAPABILITY\_AUTO\_EXPAND (uses macros or transforms, including AWS::Serverless). Empty by default, so a template that creates IAM resources fails with InsufficientCapabilities until the caller acknowledges it. | `set(string)` | `[]` | no |
| <a name="input_iam_role_arn"></a> [iam\_role\_arn](#input\_iam\_role\_arn) | ARN of the service role CloudFormation assumes for every operation on this stack, so the stack's permissions are explicit and auditable instead of borrowed from whoever runs Terraform. null (the default) makes CloudFormation use the caller's credentials; the advisory check service\_role\_not\_set warns about it. Once a stack has a role, CloudFormation keeps using it. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Stack name. CloudFormation rules: starts with a letter, then letters, digits, and hyphens only, 128 characters at most, unique per account and region. Changing it replaces the stack. | `string` | n/a | yes |
| <a name="input_notification_arns"></a> [notification\_arns](#input\_notification\_arns) | Amazon SNS topic ARNs that receive stack events, at most five. Empty by default. | `set(string)` | `[]` | no |
| <a name="input_on_failure"></a> [on\_failure](#input\_on\_failure) | What CloudFormation does when stack creation fails: ROLLBACK (the stack ends in ROLLBACK\_COMPLETE, which cannot be updated and must be replaced), DELETE (the failed stack is deleted), or DO\_NOTHING (the stack stays in CREATE\_FAILED with its partial resources, for debugging). null (the default) sends nothing, and CloudFormation applies ROLLBACK. Applies to creation only: CloudFormation never returns it, so the module ignores changes to it on an existing stack (no replacement), and an imported stack plans no change for any value. | `string` | `null` | no |
| <a name="input_parameters"></a> [parameters](#input\_parameters) | Template parameter values. Always strings on the wire: pass numbers as "3" and CommaDelimitedList values as "a,b,c". Values are stored in plan and state in clear text; never pass a secret here, resolve it in the template with a dynamic reference instead (see README, Security model). | `map(string)` | `{}` | no |
| <a name="input_stack_policy"></a> [stack\_policy](#input\_stack\_policy) | Optional stack policy that protects stack resources from unintended updates: exactly one of body (a JSON policy document, at most 16,384 bytes) or url (an https:// S3 object URL in the stack's region, at most 5,120 characters). null (the default) sets no stack policy, so every resource in the stack may be updated. | <pre>object({<br/>    body = optional(string)<br/>    url  = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the stack. CloudFormation propagates stack tags to every resource in the stack that supports tags. The module adds Name = name; a Name given here wins. At most 50 tags in total including Name (provider default\_tags also count). Keys 1 to 128 and values 1 to 256 characters of letters, digits, spaces, and \_ . : / = + - @; no aws: key prefix. | `map(string)` | `{}` | no |
| <a name="input_template"></a> [template](#input\_template) | Template source: exactly one of body (an inline JSON or YAML template, 1 to 51,200 bytes) or url (an https:// URL of a template object in Amazon S3, up to 5,120 characters; the object itself may be up to 1 MB). Write `template = { body = file("stack.yaml") }` or `template = { url = "https://..." }`. | <pre>object({<br/>    body = optional(string)<br/>    url  = optional(string)<br/>  })</pre> | n/a | yes |
| <a name="input_timeout_in_minutes"></a> [timeout\_in\_minutes](#input\_timeout\_in\_minutes) | Minutes CloudFormation lets stack creation run before it fails the create and applies on\_failure. null (the default) means no CloudFormation-side timeout. Changing it replaces the stack. Independent of the Terraform-side timeouts input. | `number` | `null` | no |
| <a name="input_timeouts"></a> [timeouts](#input\_timeouts) | Terraform-side waits for create, update, and delete, as Go durations such as "45m" or "1h30m". Unset fields keep the provider defaults (30m each). Raise them for vendor stacks that take long to converge; this does not change CloudFormation's own timeout\_in\_minutes. | <pre>object({<br/>    create = optional(string)<br/>    update = optional(string)<br/>    delete = optional(string)<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_arn"></a> [arn](#output\_arn) | Stack ARN (arn:<partition>:cloudformation:<region>:<account>:stack/<name>/<uuid>), read from the stack ID rather than constructed, because the trailing UUID is assigned by CloudFormation. |
| <a name="output_id"></a> [id](#output\_id) | Stack ID. CloudFormation stack IDs are the stack ARN, so this equals arn; it is kept under the fleet's usual name. |
| <a name="output_name"></a> [name](#output\_name) | Stack name. |
| <a name="output_outputs"></a> [outputs](#output\_outputs) | The stack's own CloudFormation Outputs as a map of output key to value. This is the composition point for anything downstream of the stack. |
<!-- END_TF_DOCS -->
