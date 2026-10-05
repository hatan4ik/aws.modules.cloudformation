# Design: aws.modules.cloudformation v1

Status: accepted 2026-10-05, released as v1.0.0. There is no live consumer yet.

## Why this module exists

This platform is Terraform-first. Every resource Terraform can express
natively is written as a Terraform resource, in a module of this series or in
a root. CloudFormation is never the default choice: a stack is a second state
store with its own drift, its own failure states, and its own permission
model, and wrapping one in Terraform hides its resources from `terraform
plan`. A reviewer sees "the stack's template changed", not which resources
will be replaced.

The module exists as a deliberate, narrow escape hatch for the cases where a
team legitimately has to provision CloudFormation from Terraform:

- **The deliverable only exists as a template.** An AWS Marketplace product,
  a Serverless Application Repository application, or a vendor integration
  that ships as a CloudFormation template and is supported only in that
  form. Rewriting it in Terraform forks it from the vendor and forfeits
  their support and upgrades.
- **The orchestration only exists in CloudFormation.** StackSets deploy one
  template to every account in a set of AWS Organizations OUs, keep
  deploying it to accounts that join those OUs later (auto-deployment), and
  bound the rollout with failure tolerance and concurrency limits. Terraform
  has no equivalent: it needs a provider configuration per account and
  region, known at plan time, and has no notion of an organization-wide,
  self-extending deployment. An org-wide security baseline (audit roles,
  AWS Config, GuardDuty member settings) is the canonical case.

**Choosing this module for anything Terraform can express natively is a
smell, not a default.** In review, a new use of this module should name which
of the two cases above it is. "We already had a template" is not one of them;
port the template.

## Purpose and scope

- The root module provisions **one** `aws_cloudformation_stack` per call, in
  the provider's account and region.
- `modules/stack-set` provisions **one** `aws_cloudformation_stack_set` and
  one `aws_cloudformation_stack_set_instance` per declared target and region.

Both are independent: the root does not call the submodule, and a caller
uses whichever matches the resource they need. They are one repository
because they share the template, parameter, and capability contract and the
same reasons to exist, not because one wraps the other.

The module does not create service roles, StackSet administration or
execution roles, template buckets, SNS topics, or Organizations trusted
access. Those have separate owners and lifecycles; the module consumes their
identifiers. It performs no data-source reads.

## Interface

Root:

- `name`; `template = { body | url }`; `parameters` (`map(string)`);
  `capabilities` (set of the three CloudFormation values).
- `on_failure` (default none, so CloudFormation applies `ROLLBACK`; changes
  ignored after create, see D11), `timeout_in_minutes` (default none),
  `notification_arns`, `stack_policy = { body | url }` (default none),
  `iam_role_arn` (default none, with an advisory check), `tags`, `timeouts`.
- Outputs: `id`, `arn` (both the stack ID, which is the ARN), `name`,
  `outputs` (the stack's CloudFormation Outputs).

`modules/stack-set`:

- `name`, `description`, `template`, `parameters`, `capabilities`, `tags`,
  `timeouts`: same shapes and rules as the root (timeouts split between the
  StackSet's update and the instances' create, update, delete).
- `permission_model = { self_managed = {...} | service_managed = {...} }`.
- `stack_instances`: map keyed `"<account_id|ou_id|root_id>/<region>"`, each
  with optional `parameter_overrides` and `retain_stack`.
- `operation_preferences`: failure tolerance, max concurrency, concurrency
  mode, region concurrency and order.
- `managed_execution_active` (default `true`).
- Outputs: `id`, `arn`, `name`, `permission_model`, `stack_instances`.

## Decisions

### D1. Template and stack policy sources are one object with an exactly-one validation

CloudFormation takes `TemplateBody` or `TemplateURL`, exactly one, and the same
for `StackPolicyBody` and `StackPolicyURL`. Two independent optional variables
would make "both" and "neither" representable and could only be rejected by a
precondition, because Terraform 1.7 validation blocks cannot reference
another variable.

`template = object({ body = optional(string), url = optional(string) })`
puts both alternatives in one value, so the exactly-one rule is a validation
on that one variable. It fails earlier than a precondition would (while
variables are evaluated, before any resource is planned), names the variable
in the error, and needs no extra machinery. The call site reads as the
choice it is: `template = { url = "..." }`. `template` has no default and is
non-nullable, so "neither" can only be written as `template = {}`, which the
validation rejects. HCL has no sum types, so this is as close to
unrepresentable as the language gets.

`stack_policy` is the same shape but nullable with a `null` default, a
documented exception: `null` means "no stack policy", which is the API
default and a legitimate choice.

### D2. The StackSet permission model is a two-branch object, not a string plus preconditions

`SELF_MANAGED` and `SERVICE_MANAGED` StackSets take disjoint inputs:
`administration_role_arn` and `execution_role_name` are valid only for the
first; `auto_deployment` is required for, and `call_as` is meaningful only
for, the second. The provider rejects a few combinations
(`auto_deployment` conflicts with the role arguments) and accepts others
that the API then rejects.

A `permission_model` string with four optional siblings and preconditions
would make every wrong combination expressible and reject it late. Instead,
`permission_model` is an object with a `self_managed` branch and a
`service_managed` branch, and each branch carries only its own fields. A
role ARN cannot be given to a service-managed StackSet, because the branch
has no field for it; `auto_deployment` is a required attribute of its
branch; `administration_role_arn` is a required attribute of the other. The
only rule left to check is "exactly one branch", a validation on the same
variable. The `SELF_MANAGED`/`SERVICE_MANAGED` string the API needs is
derived in `locals.tf` and exposed as the `permission_model` output.

`administration_role_arn` is required for self-managed StackSets even though
the API falls back to `AWSCloudFormationStackSetAdministrationRole`, and
`execution_role_name` is always sent: the roles a StackSet deploys with
should be visible in the configuration, for the same reason the root
module's `iam_role_arn` exists.

### D3. Stack instances are keyed by their identity, `"<target>/<region>"`

A stack instance is identified by its target (account or OU) and region.
Keying `stack_instances` by that pair, rather than by a caller-chosen name
with `target` and `region` fields, makes a duplicate declaration impossible
(the map literal itself collides) and makes the resource address say what
it is: `aws_cloudformation_stack_set_instance.this["ou-ab12-11111111/us-east-1"]`.
This is the lesson `aws.modules.global-accelerator` v2.0.0 learned for
endpoint groups (`"<listener>/<region>"`): when a pair is the identity,
the pair is the key. The key is split once in `locals.tf`, so an instance's
target and region cannot drift from its key.

Whether the target is an account ID or an OU/root ID depends on the
permission model, which a validation on `stack_instances` cannot see. That
cross-variable rule is a precondition on `aws_cloudformation_stack_set.this`
that names every mismatched key in one message, following the fleet's
precedent of collecting cross-variable errors on the primary resource.

A service-managed key targets exactly one OU. The API can target several OUs
in one instance resource, and can filter accounts within them
(`account_filter_type`); one OU per key keeps the identity simple and covers
the baseline use case. See Deferred to v2.

### D4. One `aws_cloudformation_stack_set_instance` per key, not `aws_cloudformation_stack_instances`

The provider has a second resource, `aws_cloudformation_stack_instances`,
that manages the cross product of a set of accounts or OUs and a set of
regions in one resource and one operation, and exposes per-instance status.
It was not chosen because:

- It forces every target into the same regions. Real baselines differ per
  OU (a sandbox OU in one region, production in four).
- Adding one account or region changes the whole resource; with one
  resource per key, the plan shows exactly the instance being added.
- Per-instance `parameter_overrides` and `retain_stack` need per-instance
  resources.

The cost is that the StackSet operations for creating instances run as
separate operations, which is why D6 turns managed execution on.

### D5. `operation_preferences` is one input, applied where each field means something

StackSet operation preferences bound how far a bad template spreads, which
is the biggest operational risk of the resource (see Failure-mode analysis).
They are exposed in full rather than hidden behind a "safe" preset, because
the right rollout speed for 5 accounts and for 500 is not the same.

The provider puts them in two places, and they mean different things:

- On `aws_cloudformation_stack_set` they govern `UpdateStackSet`: a template
  or parameter change, rolled out to every existing instance in every region
  in one operation. All fields apply, including `region_concurrency_type`
  and `region_order`. The provider has no `concurrency_mode` here.
- On `aws_cloudformation_stack_set_instance` they govern that instance's
  own create, update, and delete, each of which targets exactly one region.
  The account-level fields and `concurrency_mode` apply; region ordering
  does not, and is not sent.

One input applied in both places keeps one mental model ("this is how
cautiously this StackSet rolls out"), and `locals.tf` filters what each
resource receives. With nothing set, no block is sent and the API defaults
apply: failure tolerance 0, one account at a time. That is the slowest and
safest rollout, and the module does not pick a faster one for the caller.

Count and percentage of the same setting are mutually exclusive in the API
and rejected together at plan. The STRICT-mode rule "concurrency never
exceeds failure tolerance + 1" is not an API error, so it is an advisory
check (`max_concurrency_capped_by_failure_tolerance`) rather than a
validation.

### D6. Managed execution is on by default

The API default is off. With it off, CloudFormation runs one operation per
StackSet at a time and rejects the next with `OperationInProgressException`.
Terraform creates the instance resources of one StackSet in parallel, and
the provider retries that exception only on delete, not on create, so a
StackSet with three instances fails its first apply. With managed execution
on, StackSets runs non-conflicting operations concurrently and queues
conflicting ones. `managed_execution_active = false` remains available.

### D7. Size limits are checked in bytes

CloudFormation's limits are in bytes (51,200 for a template body, 16,384 for
a stack policy body); Terraform's `length()` counts characters. A template
with non-ASCII text in descriptions can be under the limit in characters and
over it in bytes. The validations compute the exact UTF-8 byte count from the
base64 length (`length(base64encode(s)) / 4 * 3` minus padding), and a test
pins the boundary with a multi-byte character on each side. Parameter values
(4,096 bytes) are checked in characters, a documented approximation; the
practical risk is negligible and the byte computation per value would make
the validation unreadable.

### D8. No `status` output and no status `check`

The brief for this module asked for the stack's status as an output and, if
feasible, a `check` on it to surface `ROLLBACK_COMPLETE`. Neither is
possible as specified: neither `aws_cloudformation_stack` nor the
`aws_cloudformation_stack` data source exposes `StackStatus` in provider 6.x
(verified against the 6.35.0 and 6.67.0 schemas), and neither do the StackSet
resources. A `check` with a scoped data source would need a status attribute
that does not exist and would add the module's first data-source read.

What the module does instead:

- Terraform itself already handles the common case: the provider records the
  stack ID before waiting for creation, so a failed create leaves a tainted
  resource that the next apply replaces. The README's Failure modes table
  states this for every `on_failure` value.
- The README documents the detection path (`describe-stacks`,
  `describe-stack-events`, `terraform state show`, EventBridge) and the
  manual remedies for the states Terraform cannot recover from
  (`UPDATE_ROLLBACK_FAILED`, `DELETE_FAILED`, an untainted
  `ROLLBACK_COMPLETE`).

If a later provider exposes status, adding an output is a minor release.

### D9. `parameters` is `map(string)` and not sensitive

CloudFormation parameters are strings on the wire; typing them more richly
would make the module convert and could only reject legal values. They are
not marked sensitive: marking them would hide every parameter diff from
review, which is the main thing a reviewer of a stack change needs to see.
Secrets do not belong in parameters at all (they land in state and, for
`NoEcho`, cause perpetual diffs); templates should resolve them with dynamic
references. The variable descriptions and the README say so.

The provider differs between the two resources here, and the module documents
rather than hides it: for a stack, only declared parameters are kept in
state, so leaving a parameter to its template `Default` is fine; for a
StackSet, every template parameter, including defaulted ones, must be
declared or it diffs on every plan.

### D10. `iam_role_arn` is optional, with an advisory check

A stack service role is the right default, but making it required would
force a role into every call, including integration tests and short-lived
experiments, and the API accepts its absence. It is optional, and
`check.service_role_not_set` warns on every plan while it is unset, the same
"valid but usually unintended" treatment the fleet gives to disabled
deletion protection or logging.

### D11. `on_failure`: not sent by default, ignored after create

Behaviour: `ROLLBACK` is the API default and keeps the failed stack and its
events for diagnosis; Terraform's taint-and-replace handles the recovery.
`DELETE` cleans up instead (events remain readable by stack ID for 90 days)
and is the better choice for unattended pipelines; `DO_NOTHING` keeps partial
resources for debugging. The provider's `disable_rollback` is not exposed:
the API accepts it or `OnFailure`, not both, and `on_failure` expresses
everything it does.

Wiring (changed after v1.0.0): `on_failure` defaults to `null`, and the stack
has `lifecycle { ignore_changes = [on_failure] }`. v1.0.0 sent `"ROLLBACK"`
unconditionally, which made importing an existing stack a forced
replacement. The provider's `on_failure` is `Optional` and `ForceNew` but not
`Computed`, and its Read never sets it (`DescribeStacks` does not return
`OnFailure`; Read only forces `disable_rollback = false`), so an imported
stack always has `on_failure = null` in state. Any non-null value in config
is then a ForceNew diff against null.

`default = null` alone was not enough. It fixes an import that keeps the
default, but an import with an explicit value is still replaced. Worse, every
stack created by v1.0.0 has `"ROLLBACK"` in state and would be replaced by
the upgrade (`"ROLLBACK" -> null # forces replacement`). `ignore_changes` is
the part that solves it. `on_failure` only governs the first create, so
replacing a live stack because it changed is never useful. Terraform drops
ignored values when it replans a replacement, so a stack that is replaced for
any other reason (rename, taint after a failed create) is still created with
the configured value. The trade-off is deliberate: editing `on_failure` on an
existing stack has no effect until that stack is next created.

Evidence: real `terraform plan -refresh=false` runs with hashicorp/aws
6.67.0 against a state whose stack attributes match what the provider's
import and Read produce (`on_failure` absent, `disable_rollback = false`):

| Case | State | Config | v1.0.0 | Now |
| --- | --- | --- | --- | --- |
| Import, default | null | default | `+ on_failure = "ROLLBACK" # forces replacement` | No changes |
| Import, explicit | null | `"DELETE"` | replacement | No changes |
| Upgrade from v1.0.0 | `"ROLLBACK"` | default | n/a | No changes (with `default = null` alone: `"ROLLBACK" -> null # forces replacement`) |
| Import, then rename | null | `"DELETE"`, new name | replacement | Replaced for the name; new stack created with `on_failure = "DELETE"` |
| Tainted after failed create | `"ROLLBACK"`, tainted | `"DELETE"` | replacement | Replaced; new stack created with `"DELETE"` |

`tests/on_failure.tftest.hcl` pins the ignore behaviour with the mock
provider, and fails if `ignore_changes` is removed.

### D12. Tags: `Name` first, caller wins

`merge({ Name = var.name }, var.tags)`, so a caller's `Name` overrides the
module's, the precedence two sibling modules, `aws.modules.dynamodb` among them, had
to fix after shipping the reverse. Stack and StackSet tags propagate to the
resources CloudFormation creates, so the `Name` tag reaches them too; this is
documented, and a caller who does not want it sets their own `Name`. The
50-tag limit is checked including the added `Name`.

## Failure-mode analysis

### Single stack

| Failure | Detected by | Blast radius | Recovery |
| --- | --- | --- | --- |
| Template, parameter, or capability error at create | Apply error with stack failure events | One stack, never usable | Stack is tainted; fix and apply (replace). With `on_failure = "DELETE"` the stack is gone and the next apply creates it. |
| Stack in `ROLLBACK_COMPLETE` not tainted in state | Apply error: "can not be updated" | One stack | `terraform apply -replace=...` |
| Update fails, rolls back | Apply error; status `UPDATE_ROLLBACK_COMPLETE` | None; previous template still running | Fix and apply; the refreshed template differs from config, so the update is retried. |
| Update rollback fails | Apply error; status `UPDATE_ROLLBACK_FAILED` | Stack frozen | `continue-update-rollback` (optionally skipping resources), then apply. |
| Delete fails | Destroy error; status `DELETE_FAILED` | Stack and remaining resources linger | Remove the blocker, destroy again, or `delete-stack --retain-resources`. |
| Replacement-forcing change (`name`, `timeout_in_minutes`) | Plan shows `must be replaced` | Every resource in the stack is deleted and recreated | Read the plan; use `DeletionPolicy: Retain` in the template or `prevent_destroy` in the caller for stateful stacks. |
| Template object at `template.url` overwritten | Nothing in Terraform | Next stack update deploys an unreviewed template | Use versioned keys or object lock. |

### StackSet

The defining risk is a bad template or parameter change rolling out to every
account in every region in one operation. `operation_preferences` is the
circuit breaker: failure tolerance decides when CloudFormation stops the
operation in a region and skips the remaining regions; max concurrency
decides how many accounts can break before that happens; sequential region
order with a canary region first contains a bad update to one region. The
defaults (tolerance 0, concurrency 1) stop at the first failure.

| Failure | Detected by | Blast radius | Recovery |
| --- | --- | --- | --- |
| Instance create fails in some accounts | Apply error listing account, region, and reason per failure (the provider includes the operation results) | Those accounts; their instance stacks are rolled back and deleted (StackSets creates instance stacks with `OnFailure = DELETE`) | Instance resource is tainted; fix the cause (execution role, SCP, name collision, service not enabled) and apply. |
| Template or parameter update fails in some accounts | Apply error with per-account reasons | Bounded by `operation_preferences`; remaining accounts and regions skipped | The StackSet and Terraform state already hold the new template, so the next plan is empty. Fix the cause and re-run the rollout with `update-stack-instances` (README), or fix the template and apply a new update. |
| Concurrent operations on one StackSet | `OperationInProgressException` | One apply | Prevented by managed execution (D6). |
| Auto-deployment to a new account fails | `list-stack-set-operations`; EventBridge | That account | Outside Terraform: the instance is not in state. Fix and run `update-stack-instances` for the OU. |
| `name` or `auto_deployment` changed | Plan shows the StackSet replaced | Every instance in every account deleted and recreated | Read the plan; these are replacement-forcing in the provider. |
| Instance removed | Plan shows the instance destroyed | Stacks deleted in every account of that target and region | Set `retain_stack = true` first to disassociate instead. |

## Security defaults

- No capability acknowledged unless listed; `CAPABILITY_AUTO_EXPAND` refused
  for service-managed StackSets, which cannot run macros.
- Stack service role and StackSet administration and execution roles are
  explicit inputs, and the self-managed roles are always sent.
- No secrets in parameters (documented), no sensitive output, no data
  sources, no IAM resources created by the module.
- Tags limited to 50, `aws:`-prefixed keys rejected, and key and value
  length and character set checked at plan.
- Stack policies supported but opt-in, since the right policy depends on the
  template.
- StackSet rollouts default to the slowest, safest API settings.

## Testing strategy

- Contract tests use `mock_provider`, no credentials. Root `tests/`:
  `defaults` (every argument the module sends, boundaries such as 200
  parameters, 50 tags, and a template of exactly 51,200 bytes with a
  multi-byte character), `validation` (every validation with a failing run),
  `checks` (the advisory check on and off), and `outputs` (apply mode with
  `override_resource`, isolated in its own file, proving every output
  resolves from the right attribute).
- `modules/stack-set/tests/`: `self_managed` and `service_managed` (both
  permission-model variants end to end, including OU and root targets,
  delegated admin, auto-deployment on and off), `operation_preferences` (the
  split between StackSet and instances), `validation` (every validation and
  the three preconditions), `checks`, and one apply-mode output file per
  permission model (an OU instance reports every account it reached).
- `tests/integration/smoke` applies the root module for real with a
  zero-cost `WaitConditionHandle` template and an in-place parameter update.
  There is no StackSet integration suite: it needs Organizations trusted
  access or cross-account roles, which are landing-zone infrastructure, not
  disposable fixtures.
- Static policy: `tflint` with the AWS ruleset, Checkov, Trivy, and the
  terraform-docs drift check in every directory.

## Quotas

Account-level and adjustable, so documented rather than validated:
2,000 stacks per account and region; 1,000 StackSets per administrator
account; 100,000 instances per StackSet; 10,000 concurrent instance
operations per region per administrator account; 10,000 queued operations
per StackSet.

Per-template and per-request limits, fixed, so validated where the module
sees the value: 51,200-byte template body; 200 parameters; 4,096-byte
parameter values; 5 notification topics; 50 tags; 16,384-byte stack policy;
5,120-character template and policy URLs; 128-character names. Not
validated because the module never sees the content: 1 MB template object
in S3, 500 resources and 200 outputs per template.

## Deferred to v2

Recorded deliberately; none is a defect in v1.

- **Change sets.** Reviewing a change set before executing it is
  CloudFormation's equivalent of `terraform plan`. The provider has no
  change-set resource, and approximating one with `local-exec` would put an
  unreviewable side channel in the module.
- **Drift detection.** CloudFormation drift detection is an operation, not a
  resource; running it belongs in a scheduled job or AWS Config rule, not in
  `terraform apply`.
- **Termination protection.** Not supported by the provider's
  `aws_cloudformation_stack` (no such argument in 6.x), and a caller cannot
  add `prevent_destroy` to a resource inside a module. Until the provider
  supports it, protect stateful resources with `DeletionPolicy: Retain` in
  the template and deny `cloudformation:DeleteStack` on the stack outside
  the deployment role.
- **Rollback triggers and `RetainExceptOnCreate`.** Not exposed by the
  provider's stack resource.
- **Systems Manager document templates** (`template.url` pointing at an SSM
  document). The validation accepts only `https://` S3 object URLs, which is
  every Marketplace and vendor delivery seen so far; widening the pattern is
  additive.
- **Multiple OUs and account filters per StackSet instance**
  (`deployment_targets.organizational_unit_ids` with several IDs,
  `accounts`, `account_filter_type`). One OU per key keeps the instance
  identity simple (D3); filtering is additive as an optional field.
- **`auto_deployment.depends_on_stack_sets`**, StackSet `region`
  overrides, and per-resource provider `region` arguments. No consumer needs
  them yet.
- **StackSet import of existing stacks** and `aws_cloudformation_stack_instances`
  (D4).
- **A StackSet integration suite**, once the platform has a disposable
  Organizations sandbox to run it in.

## Compatibility

- Terraform `>= 1.7.0, < 2.0.0` (the consuming platform pins 1.7.5).
- AWS provider `>= 6.35.0, < 7.0.0`. `stack_set_instance_region` (used
  instead of the deprecated `region` argument of
  `aws_cloudformation_stack_set_instance`) exists from the floor version.
