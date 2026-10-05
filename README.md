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
  template = { url = "https://vendor-templates.s3.us-east-1.amazonaws.com/agent/v4.2.0/agent.yaml?versionId=3HL4kqtJlcpXroDTDmJ.rmSpXd3dIbrHY" }

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

### Prerequisites

The quick start takes two things as given: a role CloudFormation can assume (`iam_role_arn`) and a template it can read (`template.url`). The module does not create either, deliberately: the role's permissions are whatever the template's resources need, which only the template's owner knows, and the template's storage has its own lifecycle. This is the shape of both, so nobody has to guess.

**1. The service role (`iam_role_arn`).** Optional, but without it CloudFormation acts with the credentials of whoever runs Terraform, and an advisory check warns. The role trusts `cloudformation.amazonaws.com` and carries exactly the permissions to create, update, read, and delete the template's resources. Those are template-specific: the sketch below is for [`examples/inline-template`](examples/inline-template)'s `vendor-agent.yaml`, which creates one CloudWatch Logs log group named `/vendor/<AgentName>`. For any template, the authoritative list per resource type is the `handlers` section of its registry schema (`aws cloudformation describe-type --type RESOURCE --type-name AWS::Logs::LogGroup --query Schema --output text`).

```hcl
resource "aws_iam_role" "cloudformation_vendor_agent" {
  name = "cloudformation-vendor-agent"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudformation.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Template-specific: what vendor-agent.yaml's one AWS::Logs::LogGroup needs,
# from the handler permissions of that resource type, scoped to its name.
resource "aws_iam_role_policy" "cloudformation_vendor_agent" {
  name = "vendor-agent-template"
  role = aws_iam_role.cloudformation_vendor_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
          "logs:TagResource", "logs:UntagResource", "logs:ListTagsForResource",
          "logs:GetDataProtectionPolicy", "logs:DeleteDataProtectionPolicy",
        ]
        Resource = "arn:aws:logs:us-east-1:123456789012:log-group:/vendor/*"
      },
      {
        # Describe calls are not scoped to one log group.
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups", "logs:DescribeIndexPolicies", "logs:DescribeResourcePolicies"]
        Resource = "*"
      },
    ]
  })
}

module "vendor_agent" {
  source = "git::https://github.com/hatan4ik/aws.modules.cloudformation.git?ref=<commit-sha>" # v1.0.0

  name         = "vendor-agent"
  template     = { body = file("${path.module}/vendor-agent.yaml") }
  parameters   = { AgentName = "vendor-agent", RetentionInDays = "90" }
  iam_role_arn = aws_iam_role.cloudformation_vendor_agent.arn

  # The policy must exist before CloudFormation uses the role, and must
  # outlive the stack so the delete can still run.
  depends_on = [aws_iam_role_policy.cloudformation_vendor_agent]
}
```

Things that bite:

- The identity that runs Terraform needs `iam:PassRole` on the role, or `CreateStack` is refused.
- CloudFormation uses the role for every later operation on the stack, including delete, and the role cannot be removed from the stack afterwards. Keep it (and its policy) for as long as the stack exists; the `depends_on` above makes `terraform destroy` delete the stack first. Anyone allowed to update the stack can act with the role, even without `iam:PassRole` on it, so keep it least-privilege.
- A template that creates IAM resources (`CAPABILITY_IAM`/`CAPABILITY_NAMED_IAM`, as in the quick start) needs the matching `iam:` actions in this policy too; with a missing action, the first create fails and leaves `ROLLBACK_COMPLETE` (see [Failure modes](#failure-modes)).

**2. The template source.** Prefer `template = { body = file(...) }` whenever the template fits: nothing to host, no read permissions to arrange, and the template is reviewed in the same diff. The two sources have different size limits, which the module checks where it can:

| Source | CloudFormation limit | Checked by the module |
| --- | --- | --- |
| `template.body` (sent inline in the API call as `TemplateBody`) | 51,200 bytes | Yes, in UTF-8 bytes, at plan |
| `template.url` (`TemplateURL`, an object in Amazon S3) | 1 MB for the object; the URL itself at most 5,120 characters | The URL only; the module never sees the object |

Above 51,200 bytes, or when a vendor ships the template in S3, use `template.url`. AWS documents that the **IAM identity calling `CreateStack`/`UpdateStack`** (the credentials Terraform runs with) needs `s3:GetObject` on the object, plus `kms:Decrypt` on the key if the bucket uses a customer managed KMS key. There is no CloudFormation service principal to grant in a bucket policy. In the same account, the caller's identity policy is enough; for a bucket in another account, the bucket policy must also grant that identity. A minimal private, versioned bucket with a content-addressed key, so the same plan always deploys the same bytes:

```hcl
resource "aws_s3_bucket" "templates" {
  bucket = "example-cfn-templates-123456789012"
}

resource "aws_s3_bucket_public_access_block" "templates" {
  bucket                  = aws_s3_bucket.templates.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "templates" {
  bucket = aws_s3_bucket.templates.id
  versioning_configuration { status = "Enabled" }
}

# A new key per template content: an update is a new URL, never an
# overwritten object Terraform cannot see.
resource "aws_s3_object" "vendor_agent" {
  bucket = aws_s3_bucket.templates.id
  key    = "vendor-agent/${filemd5("${path.module}/vendor-agent.yaml")}.yaml"
  source = "${path.module}/vendor-agent.yaml"
}

# Only needed when Terraform runs as a principal of another account; in the
# same account, s3:GetObject in that principal's own policy is enough.
resource "aws_s3_bucket_policy" "templates" {
  bucket = aws_s3_bucket.templates.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "TerraformDeployerReadsTemplates"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::210987654321:role/terraform-deployer" }
        Action    = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource  = "${aws_s3_bucket.templates.arn}/*"
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.templates.arn, "${aws_s3_bucket.templates.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
}

module "vendor_agent" {
  source = "git::https://github.com/hatan4ik/aws.modules.cloudformation.git?ref=<commit-sha>" # v1.0.0

  name     = "vendor-agent"
  template = { url = "https://${aws_s3_bucket.templates.bucket_regional_domain_name}/${aws_s3_object.vendor_agent.key}" }
  # ...
}
```

The same two prerequisites apply to `modules/stack-set` (the template is read once, in the administrator account); its own prerequisites, the StackSets roles or AWS Organizations setup, are in [modules/stack-set, Prerequisites](modules/stack-set/README.md#prerequisites).

For StackSets, see [`modules/stack-set`](modules/stack-set) and [`examples/stack-set-organization`](examples/stack-set-organization); for a self-managed StackSet from zero, including its IAM roles, [`modules/self-managed-roles`](modules/self-managed-roles) and [`examples/self-managed-bootstrap`](examples/self-managed-bootstrap).

## Architecture

```text
root (one stack)
├── stack.tf       aws_cloudformation_stack.this
├── variables.tf   every input, with the XOR and limit validations
├── locals.tf      tags (Name, then caller tags); inputs of the template checks
├── checks.tf      service_role_not_set, template_url_not_version_pinned,
│                  stack_policy_url_not_version_pinned, template_body_not_a_mapping (advisory)
└── outputs.tf     id, arn, name, outputs

modules/stack-set (one StackSet, N instances)
├── main.tf        aws_cloudformation_stack_set.this; aws_cloudformation_stack_set_instance.this["<target>/<region>"]
├── locals.tf      permission model, key splitting, operation preference split
├── checks.tf      no_stack_instances, max_concurrency_capped_by_failure_tolerance,
│                  template_url_not_version_pinned, template_body_not_a_mapping (advisory)
└── outputs.tf     id, arn, name, permission_model, stack_instances

modules/self-managed-roles (one IAM role per call)
├── main.tf        aws_iam_role.administration | aws_iam_role.execution, their inline policies and attachments
├── locals.tf      trust and permission policy documents (from AWS's sample templates)
├── checks.tf      execution_role_administrator_access (advisory)
└── outputs.tf     role_arn, role_name, stack_set_permission_model
```

The root module and the submodules are independent: the root never calls a submodule, and each can be used on its own. `modules/self-managed-roles` exists to produce `modules/stack-set`'s self-managed `permission_model`.

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
- Pin the template. A `template.url` whose object can be overwritten deploys whatever is there at apply time, and Terraform cannot see the change. Pin the object version with `?versionId=`; see [Template immutability](#template-immutability).
- Stack policies are opt-in. `stack_policy` can deny `Update:Replace` and `Update:Delete` for stateful resources; with none, every resource in the stack can be replaced by an update.
- Tags propagate. CloudFormation copies stack tags, including `Name`, to every resource in the stack that supports tags.

## Template immutability

**A static S3 URL gives Terraform no drift detection.** Terraform updates a stack only when an argument's value changes. `template.url` is a string; if someone overwrites the S3 object behind it, the string is the same, so `terraform plan` reports no changes, `UpdateStack` is never called, and the stack keeps running the old template while the configuration claims it runs the new one. (A later update for any other reason, such as a parameter change, would then silently pick up the new object.) The same holds for `stack_policy.url`, and for `modules/stack-set`, where the stale template is the one in every account.

**The fix is a version-pinned URL.** With versioning enabled on the bucket, every write of an object gets a new `versionId`, and CloudFormation accepts a URL that names one: `https://<bucket>.s3.<region>.amazonaws.com/<key>?versionId=<id>`. That URL changes as a string whenever the object does, which is exactly what Terraform compares. Reading a specific version needs `s3:GetObjectVersion` (not only `s3:GetObject`) for the identity that calls CloudFormation.

When the same configuration uploads the template, read `version_id` from the object resource (`aws_s3_object`, or the deprecated `aws_s3_bucket_object`); it is known after the upload, so a changed file re-uploads, gets a new version, and updates the stack in the same apply:

```hcl
resource "aws_s3_bucket_versioning" "templates" {
  bucket = aws_s3_bucket.templates.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_object" "vendor_agent" {
  bucket = aws_s3_bucket_versioning.templates.bucket # versioning on before the first upload
  key    = "vendor-agent/agent.yaml"
  source = "${path.module}/vendor-agent.yaml"

  # Re-upload when the file changes; the provider then marks version_id
  # unknown, so the stack update is planned in the same run.
  source_hash = filemd5("${path.module}/vendor-agent.yaml")
}

module "vendor_agent" {
  source = "git::https://github.com/hatan4ik/aws.modules.cloudformation.git?ref=<commit-sha>"

  name     = "vendor-agent"
  template = { url = "https://${aws_s3_bucket.templates.bucket_regional_domain_name}/${aws_s3_object.vendor_agent.key}?versionId=${aws_s3_object.vendor_agent.version_id}" }
}
```

When a separate pipeline (or a vendor) publishes the object, take the `VersionId` its upload returned (`aws s3api put-object` prints it; `aws s3api list-object-versions --bucket <bucket> --prefix <key>` lists them) and append `?versionId=<id>` to the URL you pass in. A new template is then a reviewed change to that string, not an invisible overwrite.

A content-addressed key (a new key per content, as in [Prerequisites](#prerequisites)) also changes the URL whenever the content does, as long as nobody overwrites a key. Versioning makes that guarantee hold even when someone does; appending `?versionId=` to such a URL costs nothing.

**Advisory checks.** `check.template_url_not_version_pinned` (and `check.stack_policy_url_not_version_pinned` in the root) warns on every plan when the URL is an Amazon S3 object URL (virtual-hosted or path style, including GovCloud and the `amazonaws.com.cn` China partition) without a `versionId` query parameter. It is a warning, not an error: a bucket owner may have chosen not to version, with object lock or a never-reused key instead. A non-S3 URL never reaches it, because CloudFormation reads templates only from S3 and the `url` validation rejects anything else.

**Or sidestep it with `template.body`.** An inline template is the value Terraform compares, so any content change is a diff, reviewed in the same plan. It is limited to 51,200 bytes ([Prerequisites](#prerequisites) has the limits table); above that, use a pinned URL.

## Lifecycle notes

- Parameters are strings on the wire: pass `"3"`, not `3`, and `"a,b"` for a `CommaDelimitedList`. Declare every parameter you care about; parameters you omit take the template `Default`.
- The provider normalises `template.body` (JSON and YAML), so reformatting a template does not show a diff, but any semantic change updates the stack in place.
- `outputs` is known only after apply. Downstream resources that read `outputs["Key"]` see an unknown value in the plan that creates the stack.
- Changing `name` or `timeout_in_minutes` replaces the stack (delete, then create), which destroys its resources unless the template sets `DeletionPolicy: Retain`.
- Terraform-side `timeouts` default to 30 minutes for create, update, and delete. Vendor stacks that create databases or clusters routinely need more.
- Termination protection is not supported by the provider's stack resource, and `prevent_destroy` cannot be added to a resource inside a module. Protect stateful resources with `DeletionPolicy: Retain` in the template (see [docs/DESIGN.md](docs/DESIGN.md#deferred-to-v2)).

## Testing

- Contract tests (`terraform test` in the root, `modules/stack-set`, `modules/self-managed-roles`, and `examples/self-managed-bootstrap`, run by CI) use `mock_provider`: no credentials, nothing created. Plan-mode runs assert on every argument the module sends; every validation and precondition has a failing run through `expect_failures`; apply-mode runs in their own files give the stack ID, ARN, Outputs, and instance summaries realistic values with `override_resource` and prove every output resolves from the right attribute.
- Integration suite (`tests/integration/`, run by `make integration-smoke` or the dispatch-only `integration` workflow) applies the root module for real in **your** account: a stack with one `AWS::CloudFormation::WaitConditionHandle` (no billable resource) and two Outputs, asserts the stack ARN and Outputs the real API returns, and deletes it. See [tests/integration/README.md](tests/integration/README.md).

## Design principles

- Single responsibility. The root owns one stack; `modules/stack-set` owns one StackSet and its instances. Neither creates the service roles, templates, buckets, or topics it references. `modules/self-managed-roles` owns exactly the two StackSets roles that have no other source (see [docs/DESIGN.md, D13](docs/DESIGN.md#d13-the-self-managed-stackset-roles-get-their-own-submodule)).
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
