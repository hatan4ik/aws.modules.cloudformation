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
- `modules/self-managed-roles` provisions **one** IAM role per call: the
  self-managed StackSets administration role or execution role (D13).
- `modules/service-role` provisions **one** CloudFormation stack service
  role per call, for the root module's `iam_role_arn` (D15).

All are independent: the root does not call the submodule, and a caller
uses whichever matches the resource they need. They are one repository
because they share the template, parameter, and capability contract and the
same reasons to exist, not because one wraps the other.

The root module and `modules/stack-set` do not create service roles,
StackSet roles, template buckets, SNS topics, or Organizations trusted
access. Those have separate owners and lifecycles; the modules consume their
identifiers, and neither performs data-source reads. The one exception is
`modules/self-managed-roles`, which exists only because the self-managed
StackSet roles have no other source (D13), and `modules/service-role`, a
role factory that takes the template's permissions as input instead of
guessing them (D15). The root module still takes `iam_role_arn` as an
input and never creates a role itself.

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

`modules/self-managed-roles`:

- `role = { administration = {...} | execution = {...} }`: exactly one
  branch per call. `administration`: `account_id`, `name`,
  `execution_role_name`, `target_account_ids`, `opt_in_regions`.
  `execution`: `administration_role_arns`, `name`, `policy_arns`,
  `inline_policy`.
- `tags`.
- Outputs: `role_arn`, `role_name`, `stack_set_permission_model` (the
  administration call's value for `modules/stack-set`'s `permission_model`).

`modules/service-role`:

- `name`, `path` (default `/`), `description`, `account_id` (for the trust
  conditions), `statements` (map keyed by Sid: `effect`, `actions`,
  `resources`, `conditions`), `pass_roles` (map keyed by Sid: `role_arns`,
  `services`), `permissions_boundary_arn`, `tags`.
- Outputs: `role_arn` (for the root's `iam_role_arn`; depends on the
  policies), `role_name`, `inline_policies`.

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

### D13. The self-managed StackSet roles get their own submodule

A self-managed StackSet does nothing until two roles exist: an
administration role in the administrator account that CloudFormation
assumes, and an execution role in every target account that the
administration role assumes in turn. Under the self-managed model nothing in
AWS creates them; AWS ships two sample CloudFormation templates and expects
an operator to deploy them by hand in each account before the first
StackSet. `modules/stack-set` takes the role ARN and name as inputs, so
before this submodule a developer had to leave the repository, and
Terraform, to produce its two required values. That chicken-and-egg is the
whole reason for `modules/self-managed-roles`. Unlike a stack service role,
whose permissions are entirely template-specific, the administration role is
fully determined by AWS's contract and the execution role has a documented
minimum, so the module can own them without guessing.

Shape. One call creates one role in the provider's account, chosen by a
two-branch `role` object with an exactly-one validation (the D2 pattern).
The administration role is created once and the execution role once per
target account, each with that account's provider; a single module creating
both would need provider aliases for an unknown number of accounts, which a
module cannot declare dynamically. The administration call outputs
`stack_set_permission_model`, the exact value `modules/stack-set` takes, so
the ARN and the execution role name the StackSet uses always come from the
role that was actually created.

Faithful to the AWS samples, with documented tightenings only:

- Administration role: same name, same trust principal
  (`cloudformation.amazonaws.com`), same single permission (`sts:AssumeRole`
  on `arn:*:iam::*:role/<execution role name>`) and policy name. Added: the
  `aws:SourceAccount`/`aws:SourceArn` conditions AWS recommends against the
  confused-deputy problem (which is why `account_id` is a required input:
  the module does no data-source reads), optional `target_account_ids` to
  narrow `*`, and regional principals for Regions disabled by default.
- Execution role: same name; trusts the administration role ARNs instead of
  the whole administrator account (AWS documents both; the role form means
  no other principal there can assume it). Permissions: `cloudformation:*`,
  the minimum AWS documents, and nothing else by default. The sample
  attaches `AdministratorAccess` and the AWS guide immediately says to scope
  it down; a module default would make that scoping opt-in, so the caller
  states the template's needs (`inline_policy`, `policy_arns`) and an
  advisory check warns if `AdministratorAccess` is attached anyway.
- Role path is fixed at `/`: StackSets addresses the execution role by bare
  name, so a path would make it unreachable.
- `policy_arns` is a map keyed by caller labels, so a policy created in the
  same apply (unknown ARN) can still be attached.

Out of scope: Organizations trusted access and delegated administrators,
the service-managed path's prerequisites. AWS creates that path's roles
itself, and enabling trusted access has no Terraform resource that does it
the way AWS supports (see `modules/stack-set` README, Prerequisites).

### D14. Template immutability: warn on an S3 URL without `versionId`

The defect. Terraform calls `UpdateStack` (or `UpdateStackSet`) only when an
argument's value differs from state. `template_url` is a string. When the S3
object behind it is overwritten, the string is unchanged, the plan is empty,
and the stack keeps running the old template while the configuration claims
the new one. Nothing ever surfaces it; worse, the next update for an
unrelated reason (a parameter edit) picks up the new object as a side effect
nobody reviewed. For a StackSet the stale template is the one in every target
account. `stack_policy.url` has the same flaw for the stack policy. This
breaks the module's basic promise that what is declared is what runs.

The fix the caller applies. With bucket versioning on, S3 gives every write a
new `versionId`, and CloudFormation accepts a template URL that names one
(`?versionId=<id>`, documented in the CloudFormation user guide for
versioning-enabled buckets). That URL changes as a string whenever the
object does, so Terraform sees the change and updates the stack. The version
comes from `aws_s3_object.version_id` (or the deprecated
`aws_s3_bucket_object`) when the same configuration uploads the object, which
the provider marks unknown whenever the content changes, so the upload and
the stack update happen in one apply; or from the `VersionId` an external
pipeline's upload returns, appended to the URL the caller passes. Reading a
version needs `s3:GetObjectVersion` for the identity that calls
CloudFormation. `template.body` avoids the problem entirely, because the
content is the compared value; its 51,200-byte limit (D7, README
Prerequisites) is the only reason to prefer a URL.

What the module does. Two advisory checks, `template_url_not_version_pinned`
(root and `modules/stack-set`) and `stack_policy_url_not_version_pinned`
(root), fail when the URL matches the S3 object URL host pattern (the same
pattern the `url` validations accept: virtual-hosted, legacy global and
`s3-<region>`, path style, dualstack and FIPS, GovCloud, and
`amazonaws.com.cn`) and has no `versionId` query parameter (`[?&]versionId=`,
so `versionId=` inside the key does not count).

Why a check and not a validation. An unpinned URL is valid and sometimes
deliberate: a bucket owner may use a never-reused, content-addressed key, or
object lock, instead of versioning, and the module cannot see which. The
fleet's rule for "valid but usually unintended" is an advisory check (D10).
The host-pattern guard means a non-S3 URL is never flagged; today none
reaches the check, because CloudFormation reads templates only from S3 and
the `url` validation rejects anything else, but the check stays correct if
that validation is ever widened (for example to Systems Manager document
URLs).

Not done: reading the object's current version with a data source, which
would detect drift without the caller's help but would add the module's
first data-source read and an S3 read permission to every plan.

### D15. A stack service-role factory, not a permission inferrer

Why it exists. The root module takes `iam_role_arn` as an input: dependency
inversion, because what a stack's role may do is decided by its template,
which the module cannot see. That stays. But "bring your own role" with
nothing to help has a predictable failure mode: the stack fails with
`AccessDenied`, and the quickest fix is a role with `AdministratorAccess`.
That role then acts for every stack that uses it, and CloudFormation lets
anyone allowed to update such a stack act with it, even without
`iam:PassRole` on it. `modules/service-role` makes the narrow role as cheap
to write as the wide one: the caller lists statements, the module does the
rest.

What it deliberately does not do:

- Infer permissions from a template. Out of scope, and not a gap to close
  later: the mapping from a template's properties to the API calls each
  resource handler makes lives in the registry schemas, changes with them,
  and depends on property values. The caller must know what the template
  needs; the module's descriptions and README point at the schema handlers
  as the source.
- Accept managed policy ARNs. `modules/self-managed-roles` has
  `policy_arns`; this module does not, because a `policy_arns` input would
  make `AdministratorAccess` a one-line choice again. A caller who really
  needs a managed policy attaches it to the `role_name` output, visibly.
- Serve `modules/stack-set`. It has no stack service-role input: a StackSet
  takes an administration role ARN (whose only permission is assuming
  execution roles) and an execution role name, which are
  `modules/self-managed-roles` (D13). A stack service role in that slot
  would be the wrong role.

Interface. `statements` uses the statement shape this fleet already uses
for role policies (`aws.modules.ecs-service`'s `task_role_statements`, and
the resource-policy inputs of `aws.modules.s3`, `aws.modules.kms`, and
`aws.modules.dynamodb`): a map keyed by Sid, each `{ effect, actions,
resources, conditions }`. A map, not a list, so the key is the Sid and
reordering never changes the plan. `pass_roles` models `iam:PassRole` the
way AWS recommends scoping it: on named roles (a wildcard is allowed in the
name, for the generated names of roles the template creates), and only to
named services through `iam:PassedToService`. Both lists are required, so
"any role to any service" cannot be written; `role/*` can, and an advisory
check warns about it, as another does about an `Allow` of `*`. The two
documents are separate inline policies (`CloudFormationTemplate`,
`CloudFormationPassRole`), so a caller's Sid can never collide with a
pass-role Sid; a precondition enforces IAM's 10,240-character aggregate
inline policy limit.

Trust. Only `cloudformation.amazonaws.com`, with
`modules/self-managed-roles`' confused-deputy keys (`aws:SourceAccount`,
`aws:SourceArn`) bound to `account_id`, but with the `IfExists` operators
and an `aws:SourceArn` of `arn:*:cloudformation:*:<account_id>:*`. The
difference is deliberate: AWS documents these keys for the StackSets
administration role (D13), registry extension roles, and Git sync roles,
but its pages on the stack service role (the CloudFormation user guide's
"CloudFormation service role" and the prescriptive guidance on
least-privilege CloudFormation) show only the plain trust policy, and do not
say that CloudFormation puts either key in the request context when it
assumes a stack's role. A plain `StringEquals`/`ArnLike` on a key that is
absent evaluates false, which would make every stack using the role fail to
create. `IfExists` binds whenever the key is present and otherwise reduces
to AWS's documented trust policy. The `aws:SourceArn` pattern is AWS's own
account-wide example from its confused-deputy page, because the ARN
CloudFormation would report (stack or change set) is undocumented for this
role. Not verified against a real stack in this change; the integration
suite is the place to prove it and, if the keys turn out to be present, to
tighten the operators.

Ordering. `role_arn` has `depends_on` on both inline policies. A module
output otherwise depends only on what its expression references, the role,
so `terraform graph` of `examples/scoped-service-role` showed the stack
depending on `aws_iam_role.this` alone: the stack could be created before
its policies were attached, and on destroy the policies could be removed
before the stack, leaving a delete CloudFormation cannot perform. With the
`depends_on`, the graph shows the stack depending on both policies.

### D16. A body that parses but is not a template mapping gets an advisory check

The brief asked for plan-time syntax pre-validation of `template.body`:
warn when neither `jsondecode` nor `yamldecode` parses it. Two findings
changed the design.

1. `yamldecode` rejects every CloudFormation short-form intrinsic. Verified
   on Terraform 1.7.5 and 1.16.5: `yamldecode("a: !Ref X")` fails with
   `unsupported tag "!Ref"`, and the same for `!GetAtt`, `!Sub`, `!Join`,
   `!If`, `!Equals`, `!Not`, `!Condition`, `!Base64`, `!GetAZs`,
   `!Transform`, `!Length`, `!ToJsonString`, in flow and block style. Only
   standard `!!` tags decode. A naive check would warn on almost every real
   YAML template.
2. The provider already validates syntax. `aws_cloudformation_stack` and
   `aws_cloudformation_stack_set` reject a `template_body` that is not valid
   JSON or YAML at plan, as a hard error that names the line and column
   (verified with the mock provider on 6.35.0 and 6.67.0: bad indentation,
   tab indentation, unclosed flow sequences and quotes, unclosed JSON,
   trailing commas in JSON), and accept short-form tags. A module check for
   syntax errors would never be reported, because the provider error stops
   the plan first.

What the provider accepts and CloudFormation does not is a body that is
valid JSON or YAML but not a mapping. The common case is a file path passed
as the body (`body = "stack.yaml"` instead of `body = file("stack.yaml")`),
which is a valid YAML string and fails only at apply. So the check is
`template_body_not_a_mapping`: it passes when `keys(jsondecode(body))`
succeeds, or `keys(yamldecode(body'))` succeeds where `body'` is the body
with every local tag (`!` and a name, at the start of a node) removed. The
removal turns `!GetAtt [B, Arn]` into `[B, Arn]` and `!Ref X` into `X`,
which keeps the document's structure; removing text inside a quoted string
or a block scalar cannot make valid YAML invalid. It was checked against
every template in this repository and a template exercising all short-form
functions with no false warning.

It is an advisory check, not a precondition, because the tag removal is a
heuristic over a grammar Terraform does not implement, and CloudFormation's
parser is the authority. A false warning costs a line of output; a false
precondition would block a valid template.

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

- No capability acknowledged unless listed. `CAPABILITY_AUTO_EXPAND` is
  accepted for service-managed StackSets, as `CreateStackSet` accepts it.
  What AWS rejects is a template that references a macro or transform, and
  the module cannot see that, so it is documented rather than checked. v1.0.0
  refused the capability itself, which was stricter than AWS and still did not
  catch the real failure.
- Stack service role and StackSet administration and execution roles are
  explicit inputs, and the self-managed roles are always sent.
- No secrets in parameters (documented), no sensitive output, no data
  sources. The root module and `modules/stack-set` create no IAM resources;
  `modules/self-managed-roles` creates exactly the two StackSets roles, with
  no permission broader than AWS's samples and the execution role reduced to
  AWS's documented minimum by default (D13). `modules/service-role` grants
  only the caller's statements, accepts no managed policy, and warns on an
  `Allow` of `*` and on `iam:PassRole` over every role (D15).
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
  `checks` (the advisory check on and off), `template_checks` (D14 and D16:
  pinned and unpinned URLs in every S3 host form, a real short-form YAML
  template that `yamldecode` alone rejects, and bodies that are not
  mappings), and `outputs` (apply mode with
  `override_resource`, isolated in its own file, proving every output
  resolves from the right attribute).
- `modules/stack-set/tests/`: `self_managed` and `service_managed` (both
  permission-model variants end to end, including OU and root targets,
  delegated admin, auto-deployment on and off), `operation_preferences` (the
  split between StackSet and instances), `validation` (every validation and
  the two preconditions), `checks`, `template_checks`, and one apply-mode
  output file per permission model (an OU instance reports every account it
  reached).
- `modules/self-managed-roles/tests/`: `administration` and `execution`
  (each policy document compared with AWS's sample), `validation`,
  `checks`, and one apply-mode output file per branch; the administration
  one also feeds `stack_set_permission_model` into `modules/stack-set` and
  asserts the StackSet sends both values.
- `modules/service-role/tests/`: `role` (trust and template policy
  documents compared exactly), `pass_role`, `validation` (every validation
  and the size precondition), `checks`, and `outputs` (apply mode; also
  feeds `role_arn` into the root module and asserts the stack sends it).
- `examples/self-managed-bootstrap/tests/wiring` applies the whole example
  with both providers mocked, proving the three calls compose.
- `examples/scoped-service-role/tests/wiring` applies the example mocked and
  asserts the scoping: the template's two resource types, actions of exactly
  their two services, on exactly their two resources, no `*`.
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
