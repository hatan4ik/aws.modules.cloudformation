# stack-set

Owns one CloudFormation StackSet and its stack instances: `aws_cloudformation_stack_set.this` and one `aws_cloudformation_stack_set_instance.this["<target>/<region>"]` per declared target and region. A StackSet deploys one template to many accounts and regions in managed, failure-bounded operations, which is the one thing about CloudFormation a multi-account Terraform platform has no native equivalent for. It is a separate module from the root because it is a different resource shape with a different failure model, not a variant of a single stack.

Use it for organization-wide baselines (security tooling, audit roles, AWS Config) that must reach every account in a set of OUs, including accounts that join later. If you manage each target account with its own Terraform root already, a plain resource in that root is usually simpler.

## Usage

```hcl
module "audit_role_baseline" {
  source = "git::https://github.com/hatan4ik/aws.modules.cloudformation.git//modules/stack-set?ref=<commit-sha>" # v1.0.0

  name     = "security-audit-role"
  template = { url = "https://baseline-templates.s3.us-east-1.amazonaws.com/audit-role/v3.yaml" }

  parameters   = { SecurityAccountId = "111111111111", RoleName = "security-audit" }
  capabilities = ["CAPABILITY_NAMED_IAM"]

  permission_model = {
    service_managed = {
      auto_deployment = { enabled = true }
      call_as         = "DELEGATED_ADMIN"
    }
  }

  stack_instances = {
    "ou-ab12-11111111/us-east-1" = {}
    "ou-ab12-22222222/us-east-1" = { parameter_overrides = { RoleName = "security-audit-sandbox" } }
  }

  operation_preferences = {
    failure_tolerance_count = 1
    max_concurrent_count    = 2
  }

  tags = { Owner = "security" }
}
```

## Prerequisites

A StackSet needs permission to deploy into other accounts before this module can do anything, and the two permission models get it from different places. Set them up once, before the first apply.

### Self-managed: two IAM roles

Every self-managed StackSet needs an **administration role** in the account that owns the StackSet and an **execution role** in every target account that trusts it. Nothing in AWS creates them under this model. [`modules/self-managed-roles`](../self-managed-roles) does, and its `stack_set_permission_model` output is this module's `permission_model`:

```hcl
permission_model = module.stack_set_administration_role.stack_set_permission_model
```

[`examples/self-managed-bootstrap`](../../examples/self-managed-bootstrap) is the full chain in one configuration. Also needed: `iam:PassRole` on the administration role for whoever runs Terraform. The self-managed model needs no AWS Organizations setup at all.

### Service-managed: AWS Organizations, in this order

AWS creates the deployment roles in member accounts itself, but only after the organization is set up for it. Steps 1 to 3 run **in the organization's management account**, as an administrator; follow them top to bottom.

1. **The organization must have all features enabled.** With only consolidated billing, a service-managed StackSet cannot be created. Check:

   ```sh
   aws organizations describe-organization --query Organization.FeatureSet --output text   # must print ALL
   ```

   If it prints `CONSOLIDATED_BILLING`, enable all features. This sends a handshake to every *invited* member account, and the change completes only after each of them accepts and the management account accepts the final `ENABLE_ALL_FEATURES` handshake; accounts created from the organization need no action:

   ```sh
   aws organizations enable-all-features
   aws organizations list-handshakes-for-organization   # track acceptance
   ```

   If the organization is managed in Terraform, `aws_organizations_organization` with `feature_set = "ALL"` calls the same `EnableAllFeatures` (it starts the handshake; it does not wait for the accounts to accept).

2. **Activate trusted access for StackSets.** This is a CloudFormation API call, not an Organizations one:

   ```sh
   aws cloudformation activate-organizations-access
   aws cloudformation describe-organizations-access --query Status --output text        # must print ENABLED
   ```

   It also creates the service-linked role `AWSServiceRoleForCloudFormationStackSetsOrgAdmin` in the management account; the per-member `AWSServiceRoleForCloudFormationStackSetsOrgMember` roles and `stacksets-exec-*` roles are created when a StackSet first deploys to an account. The console equivalent is the **Activate trusted access** banner on the CloudFormation StackSets page.

   **No Terraform resource does this.** The AWS provider (checked up to 6.67.0) has no resource that calls `ActivateOrganizationsAccess`. `aws_organizations_aws_service_access` and the `aws_service_access_principals` argument of `aws_organizations_organization` call the Organizations `EnableAWSServiceAccess` API instead, and AWS states that trusted access for StackSets can only be enabled through CloudFormation (the CloudFormation API also creates the service-linked role above); the provider's own documentation recommends each service's own tooling over that resource for the same reason. Run the CLI command once, by hand or from your landing-zone pipeline.

   If your `aws_organizations_organization` manages `aws_service_access_principals`, Terraform treats that list as the complete set of enabled services and disables any other one on the next apply. Run `aws organizations list-aws-service-access-for-organization` after step 2 and add every StackSets principal it shows to the list (Terraform then makes no call for it). Disabling trusted access programmatically removes StackSets' permissions in the organization; AWS recommends doing it only from the CloudFormation console, and every delegated administrator must be deregistered first.

3. **Register a delegated administrator (only for `call_as = "DELEGATED_ADMIN"`).** A delegated administrator runs StackSets from a member account, which keeps day-to-day StackSets work (and its credentials) out of the management account; skip this step for `call_as = "SELF"`. Trusted access (step 2) must already be active, and the account must be a member of the organization. At most five accounts can be registered at once, and AWS lists the Regions where delegated administrators can be registered: us-east-1, us-east-2, us-west-1, us-west-2, ap-south-1, ap-northeast-1, ap-northeast-2, ap-southeast-1, ap-southeast-2, ca-central-1, eu-central-1, eu-west-1, eu-west-2, eu-west-3, eu-north-1, il-central-1, sa-east-1, us-gov-east-1, and us-gov-west-1.

   ```sh
   aws organizations register-delegated-administrator \
     --service-principal=member.org.stacksets.cloudformation.amazonaws.com \
     --account-id=<member-account-id>
   aws organizations list-delegated-administrators \
     --service-principal=member.org.stacksets.cloudformation.amazonaws.com   # verify
   ```

   Unlike step 2, this one has a Terraform resource, run with management-account credentials:

   ```hcl
   resource "aws_organizations_delegated_administrator" "stacksets" {
     account_id        = "222222222222"
     service_principal = "member.org.stacksets.cloudformation.amazonaws.com"
   }
   ```

   A delegated administrator can deploy to every account in the organization; the management account cannot limit it to particular OUs or operations.

4. **Permissions of the identity that runs Terraform** (in the management account for `SELF`, in the delegated administrator account for `DELEGATED_ADMIN`): permission to manage StackSets and their instances (`cloudformation:*StackSet*` and `cloudformation:*StackInstance*` cover every call this module makes, including the operation polling), plus `organizations:ListDelegatedAdministrators` for a delegated administrator, which AWS calls out explicitly. Operations started by a delegated administrator are still performed by the management account.

   Check that a delegated administrator sees trusted access:

   ```sh
   aws cloudformation describe-organizations-access --call-as DELEGATED_ADMIN --query Status --output text
   ```

Then set `permission_model.service_managed.call_as` to match where Terraform runs, and target OU or root IDs from `aws organizations list-roots` / `list-organizational-units-for-parent`. CloudFormation never deploys a service-managed StackSet to the management account, even when its OU or the root is targeted; manage anything the management account needs separately. Service-managed StackSets also cannot target accounts outside the organization, and do not support nested stacks or templates with macros or transforms.

To deploy to a Region that is disabled by default (opt-in), enable that Region in the administrator or management account as well as in the target accounts.

AWS sources: [Activate trusted access](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-activate-trusted-access.html), [Register a delegated administrator](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-delegated-admin.html), [CloudFormation StackSets and AWS Organizations](https://docs.aws.amazon.com/organizations/latest/userguide/services-that-can-integrate-cloudformation.html), [Create StackSets with service-managed permissions](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-associate-stackset-with-org.html), [Grant self-managed permissions](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-prereqs-self-managed.html), [Regions disabled by default](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-opt-in-regions.html).

## Behaviour

- Permission model. `permission_model` is an object with two mutually exclusive branches, so the inputs of one model cannot be given to the other:
  - `self_managed = { administration_role_arn, execution_role_name }`: you created `administration_role_arn` in this account and a role named `execution_role_name` (default `AWSCloudFormationStackSetExecutionRole`) in every target account that trusts it (for example with [`modules/self-managed-roles`](../self-managed-roles)). Both are always sent, so who deploys what is explicit. Targets are 12-digit account IDs.
  - `service_managed = { auto_deployment = { enabled, retain_stacks_on_account_removal }, call_as }`: AWS Organizations trusted access creates the roles. `auto_deployment` is required: `enabled` decides whether accounts joining a targeted OU get an instance automatically, and `retain_stacks_on_account_removal` (default `false`) whether an account leaving keeps its stack. `call_as` is `SELF` (management account, the default) or `DELEGATED_ADMIN`. Targets are OU IDs or the root ID. A template with macros or transforms fails for this model (see [Failure modes](#failure-modes)). The organization must be set up first; see [Prerequisites](#prerequisites).
- Instances. Each `stack_instances` key is `"<target>/<region>"` and becomes one instance resource: for `self_managed`, a stack in that one account; for `service_managed`, a stack in every account of that OU (or of the whole organization, for `r-...`). The key is the identity, so the same target and region cannot be declared twice. A key whose target does not match the permission model fails the plan with every offending key named. `parameter_overrides` replaces StackSet parameter values for one instance; `retain_stack = true` keeps the stack in the target account when the instance is removed.
- Operation preferences. `operation_preferences` is split between the two resources. The StackSet gets the account-level settings plus `region_concurrency_type` and `region_order`; they govern template and parameter updates, which roll out to every existing instance in one operation. Each instance gets the account-level settings plus `concurrency_mode` for its own create, update, and delete; region ordering does not apply to an operation that targets one region. Unset, no block is sent and CloudFormation's defaults apply: failure tolerance 0, one account at a time.
- Managed execution is on by default (`managed_execution_active = true`, where the API default is off). Terraform creates the instances of one StackSet in parallel, and without managed execution every operation after the first fails with `OperationInProgressException`; with it, StackSets queues them.
- Parameters. Declare every template parameter in `parameters`, including ones with a `Default`: the provider does not read template defaults back for a StackSet, so an omitted one shows a diff on every plan. `NoEcho` parameters are not supported; they read back as `****` and diff on every plan. Use a dynamic reference in the template instead.
- Tags. The module adds `Name = name`; a caller's `Name` wins. StackSet tags propagate to every instance stack and to the supported resources in it.

## Failure modes

The biggest operational risk of a StackSet is a bad template reaching every account at once. A StackSet operation (creating instances, or updating the template or parameters) runs per region, a few accounts at a time, and `operation_preferences` is the circuit breaker:

| Setting | What it bounds |
| --- | --- |
| `failure_tolerance_count` / `failure_tolerance_percentage` | How many accounts in a region may fail before CloudFormation stops the operation in that region and does not start it in any later region. Default 0: the first failure stops everything. |
| `max_concurrent_count` / `max_concurrent_percentage` | How many accounts are worked on at once, so how many can be broken before a failure is noticed. Default 1. |
| `concurrency_mode` | `STRICT_FAILURE_TOLERANCE` (default) lowers concurrency as failures accumulate and never runs more than tolerance + 1 accounts at once; `SOFT_FAILURE_TOLERANCE` keeps the configured concurrency regardless of failures. The `max_concurrency_capped_by_failure_tolerance` check warns when strict mode silently caps `max_concurrent_count`. |
| `region_concurrency_type` / `region_order` | `SEQUENTIAL` with a canary region first means a bad update stops in the first region instead of reaching all of them in parallel. |

The defaults are the slowest and safest rollout. Widen them deliberately; for a large organization, something like 10 percent concurrency with a tolerance of 1, one region at a time, is a common middle ground.

What a failure looks like, and what to do:

- A failed operation fails the apply. The provider waits for the operation and, when it fails, puts one line per account and region (`Account (...), Region (...), FAILED: <reason>`) in the error. For an update of the StackSet itself, or to look again later, list them with:

  ```sh
  aws cloudformation list-stack-set-operations --stack-set-name <name> --max-items 5
  aws cloudformation list-stack-set-operation-results --stack-set-name <name> --operation-id <id> \
    --query 'Summaries[?Status!=`SUCCEEDED`].[Account,Region,Status,StatusReason]'
  aws cloudformation list-stack-instances --stack-set-name <name> \
    --query 'Summaries[?StackInstanceStatus.DetailedStatus!=`SUCCEEDED`]'
  ```

  For a service-managed StackSet run from a delegated administrator account, add `--call-as DELEGATED_ADMIN`.
- Instances whose stacks failed are `OUTDATED` (with a detailed status of `FAILED` or `CANCELLED` for those never attempted after the stop). They keep running the previous template version where an update failed; where a create failed, the instance stack in that account was rolled back and deleted (StackSets always creates instance stacks with `OnFailure = DELETE`).
- Retrying a failed instance create is a normal apply: the instance was recorded before the wait, so Terraform marks it tainted and replaces it on the next apply.
- Retrying a failed template or parameter update is not. CloudFormation stores the new template on the StackSet even when the rollout to instances fails, and Terraform stores it in state, so the next plan shows no changes while the failed instances stay `OUTDATED`. Fix the cause in the target accounts, then re-run the rollout outside Terraform, with the same operation preferences:

  ```sh
  aws cloudformation update-stack-instances --stack-set-name <name> \
    --deployment-targets OrganizationalUnitIds=<ou-id> --regions <region> \
    --operation-preferences FailureToleranceCount=0,MaxConcurrentCount=1
  ```

  (`--accounts <id>` instead of `--deployment-targets` for a self-managed StackSet.) If the fix is in the template itself, change the template and apply: that is a new update and rolls out to every instance again. Typical causes are a missing or mistrusting execution role in the target account (self-managed), a resource name already taken in one account, a service not enabled in a region, or an SCP denying the action.
- Accounts reached through auto-deployment are not in Terraform state. Their failures appear in `list-stack-set-operations` as auto-deployment operations, and `operation_preferences` does not apply to them.
- Changing `name`, or anything in `auto_deployment`, replaces the StackSet: every instance is deleted, then everything is recreated. Changing an instance key replaces that instance. Read the plan before applying either.
- Deleting an instance deletes its stacks in the target accounts unless `retain_stack = true`.
- A service-managed StackSet cannot run macros or transforms (including `AWS::Serverless` and `AWS::Include`). CloudFormation accepts `CAPABILITY_AUTO_EXPAND` for it, but a template that references a macro fails at apply; the module cannot detect that from the template. Expand the template first (create a change set for it in a scratch stack and deploy the output of `aws cloudformation get-template --template-stage Processed`), or use `self_managed`.

Detect drift and failed instances outside Terraform with an EventBridge rule on `aws.cloudformation` `CloudFormation StackSet Operation Status Change` events whose status is `FAILED`, or periodically with the `list-stack-instances` query above.

## Quotas

1,000 StackSets per administrator account (adjustable), 100,000 instances per StackSet, 10,000 concurrent instance operations per region across all StackSets, and 10,000 queued operations per StackSet. The module does not validate them: they are account-level and adjustable.

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
| [aws_cloudformation_stack_set.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudformation_stack_set) | resource |
| [aws_cloudformation_stack_set_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudformation_stack_set_instance) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_capabilities"></a> [capabilities](#input\_capabilities) | Capabilities the template needs acknowledged: CAPABILITY\_IAM, CAPABILITY\_NAMED\_IAM, CAPABILITY\_AUTO\_EXPAND. CloudFormation accepts CAPABILITY\_AUTO\_EXPAND for either permission model, but a service-managed StackSet cannot run macros or transforms (including AWS::Serverless and AWS::Include): a template that references one fails at apply even with the capability. The module cannot detect a macro in the template, so expand it first or use self\_managed. | `set(string)` | `[]` | no |
| <a name="input_description"></a> [description](#input\_description) | Optional StackSet description, 1 to 1,024 characters. null (the default) sets none. | `string` | `null` | no |
| <a name="input_managed_execution_active"></a> [managed\_execution\_active](#input\_managed\_execution\_active) | Whether StackSets runs non-conflicting operations concurrently and queues conflicting ones. true by default, unlike the API: Terraform creates the instances of one StackSet in parallel, and without managed execution the second concurrent operation fails with OperationInProgressException. | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | StackSet name. Same rules as a stack name: starts with a letter, then letters, digits, and hyphens only, 128 characters at most, unique per administrator account and region. Changing it replaces the StackSet and every instance. | `string` | n/a | yes |
| <a name="input_operation_preferences"></a> [operation\_preferences](#input\_operation\_preferences) | How far and how fast one StackSet operation rolls out, which bounds the blast radius of a bad template. Unset fields keep the CloudFormation defaults: failure tolerance 0 and one account at a time, the slowest and safest rollout.<br/><br/>failure\_tolerance\_count or failure\_tolerance\_percentage (at most one): failures per region tolerated before CloudFormation stops the operation in that region and skips later regions. max\_concurrent\_count or max\_concurrent\_percentage (at most one): accounts worked on at once. concurrency\_mode: STRICT\_FAILURE\_TOLERANCE (the API default; concurrency never exceeds failure tolerance + 1) or SOFT\_FAILURE\_TOLERANCE. region\_concurrency\_type (SEQUENTIAL or PARALLEL) and region\_order: how regions are ordered within one operation.<br/><br/>The StackSet's settings govern template and parameter updates, which roll out to every existing instance in one operation. Each instance resource applies the account-level settings and concurrency\_mode to its own create, update, and delete; region\_order and region\_concurrency\_type do not apply there, because each instance targets one region. | <pre>object({<br/>    failure_tolerance_count      = optional(number)<br/>    failure_tolerance_percentage = optional(number)<br/>    max_concurrent_count         = optional(number)<br/>    max_concurrent_percentage    = optional(number)<br/>    concurrency_mode             = optional(string)<br/>    region_concurrency_type      = optional(string)<br/>    region_order                 = optional(list(string))<br/>  })</pre> | `{}` | no |
| <a name="input_parameters"></a> [parameters](#input\_parameters) | Template parameter values for every instance, as strings. Declare every template parameter here, including ones with a Default: the provider does not read template defaults back for a StackSet, so an omitted one shows a diff on every plan. Values are stored in plan and state in clear text; NoEcho parameters are not supported (see README). | `map(string)` | `{}` | no |
| <a name="input_permission_model"></a> [permission\_model](#input\_permission\_model) | How StackSets gets permission to deploy into target accounts. Set exactly one branch; each carries only the inputs its model accepts, so an input of the other model cannot be expressed.<br/><br/>self\_managed: you created the roles. administration\_role\_arn (required) is the role in this administrator account that CloudFormation assumes; execution\_role\_name (default AWSCloudFormationStackSetExecutionRole) is the role it then assumes in every target account. Targets are account IDs.<br/><br/>service\_managed: AWS Organizations trusted access creates the roles. auto\_deployment (required) decides whether accounts that join a targeted OU get an instance automatically (enabled) and whether their stacks are kept when they leave (retain\_stacks\_on\_account\_removal, default false). call\_as is SELF (default; running in the management account) or DELEGATED\_ADMIN (running in a registered delegated administrator account). Targets are OU IDs or the organization root ID. Changing auto\_deployment replaces the StackSet. | <pre>object({<br/>    self_managed = optional(object({<br/>      administration_role_arn = string<br/>      execution_role_name     = optional(string, "AWSCloudFormationStackSetExecutionRole")<br/>    }))<br/>    service_managed = optional(object({<br/>      auto_deployment = object({<br/>        enabled                          = bool<br/>        retain_stacks_on_account_removal = optional(bool, false)<br/>      })<br/>      call_as = optional(string, "SELF")<br/>    }))<br/>  })</pre> | n/a | yes |
| <a name="input_stack_instances"></a> [stack\_instances](#input\_stack\_instances) | Stack instances keyed "<target>/<region>", one aws\_cloudformation\_stack\_set\_instance each. The key is the instance's identity, so the same target and region cannot be declared twice. The target is a 12-digit account ID for self\_managed, or an OU ID (ou-xxxx-yyyyyyyy) or the organization root ID (r-xxxx) for service\_managed, which deploys to every account in it. The region is where the instance stack is created.<br/><br/>parameter\_overrides replaces StackSet parameter values for this instance only. retain\_stack = true keeps the deployed stack in the target account when the instance is removed (the stack is disassociated, not deleted). Changing a key replaces that instance. | <pre>map(object({<br/>    parameter_overrides = optional(map(string), {})<br/>    retain_stack        = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the StackSet, which CloudFormation propagates to every instance stack and to the supported resources in them. The module adds Name = name; a Name given here wins. At most 50 tags in total including Name (provider default\_tags also count). Keys 1 to 128 and values 1 to 256 characters of letters, digits, spaces, and \_ . : / = + - @; no aws: key prefix. | `map(string)` | `{}` | no |
| <a name="input_template"></a> [template](#input\_template) | Template source: exactly one of body (an inline JSON or YAML template, 1 to 51,200 bytes) or url (an https:// URL of a template object in Amazon S3, up to 5,120 characters; the object itself may be up to 1 MB). Same shape and rules as the root module's template. | <pre>object({<br/>    body = optional(string)<br/>    url  = optional(string)<br/>  })</pre> | n/a | yes |
| <a name="input_timeouts"></a> [timeouts](#input\_timeouts) | Terraform-side waits as Go durations such as "2h": stack\_set\_update for template and parameter rollouts across every instance, and instance\_create, instance\_update, instance\_delete for each instance resource. Unset fields keep the provider defaults (30m each), which a rollout across many accounts can exceed. | <pre>object({<br/>    stack_set_update = optional(string)<br/>    instance_create  = optional(string)<br/>    instance_update  = optional(string)<br/>    instance_delete  = optional(string)<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_arn"></a> [arn](#output\_arn) | StackSet ARN. |
| <a name="output_id"></a> [id](#output\_id) | StackSet ID (<name>:<uuid>), as CloudFormation assigns it. |
| <a name="output_name"></a> [name](#output\_name) | StackSet name. |
| <a name="output_permission_model"></a> [permission\_model](#output\_permission\_model) | SELF\_MANAGED or SERVICE\_MANAGED, derived from the permission\_model branch that was set. |
| <a name="output_stack_instances"></a> [stack\_instances](#output\_stack\_instances) | Stack instances keyed like stack\_instances ("<target>/<region>"): id (the provider's instance ID), region, organizational\_unit\_id (null for self\_managed), account\_ids (the one target account for self\_managed; every account the OU deployment reached for service\_managed), and stack\_ids (the instance stack ARNs in those accounts). |
<!-- END_TF_DOCS -->
