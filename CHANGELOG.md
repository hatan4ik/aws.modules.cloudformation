# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

### Added

- Submodule `self-managed-roles`: creates the IAM roles a self-managed StackSet needs, one per call: `role = { administration = {...} }` in the administrator account or `role = { execution = {...} }` in a target account. A translation of AWS's sample templates `AWSCloudFormationStackSetAdministrationRole.yml` and `AWSCloudFormationStackSetExecutionRole.yml`, with the confused-deputy trust conditions AWS recommends, the execution role trusting the administration role ARN instead of the whole administrator account, and the execution role limited to `cloudformation:*` (AWS's documented minimum) plus caller-supplied `inline_policy`/`policy_arns` instead of the sample's `AdministratorAccess`. Outputs `role_arn`, `role_name`, and `stack_set_permission_model`, which plugs directly into `modules/stack-set`'s `permission_model`. Contract tests cover every policy document, validation, and output, and feed the output into `modules/stack-set`.
- Example `self-managed-bootstrap`: zero to a deployed self-managed StackSet in one configuration. It composes `modules/self-managed-roles` (administration role in the administrator account, execution role in a target account through an `assume_role` provider, scoped to what the template creates) with `modules/stack-set`, and has its own credential-free test that applies all three calls with both providers mocked.
- `modules/stack-set` README: a Prerequisites section. Self-managed points to `modules/self-managed-roles`; service-managed is an ordered checklist with commands: all features enabled in AWS Organizations, trusted access activated with `aws cloudformation activate-organizations-access` (no Terraform resource calls that API; `aws_organizations_aws_service_access` and `aws_service_access_principals` call Organizations `EnableAWSServiceAccess`, which AWS does not support for StackSets), a delegated administrator registered with `aws organizations register-delegated-administrator` or `aws_organizations_delegated_administrator` for `call_as = "DELEGATED_ADMIN"`, and the caller's permissions.

### Fixed

- `modules/stack-set` README still said `CAPABILITY_AUTO_EXPAND` is rejected for service-managed StackSets, which stopped being true when the precondition was removed; it now points to the macro limitation in Failure modes.
- The S3 website-endpoint exclusion on `template.url` (root and `stack-set`) and `stack_policy.url` checked the whole URL for the substring `s3-website`, so a REST-endpoint URL such as `https://bucket.s3.us-east-1.amazonaws.com/templates/s3-website.yaml`, or a bucket whose name contains `s3-website`, was wrongly rejected. It now matches only the website-endpoint host forms `<bucket>.s3-website-<region>.amazonaws.com` and `<bucket>.s3-website.<region>.amazonaws.com` (and `.com.cn`).
- `tags` (root and `stack-set`) now validates each key (1 to 128 characters) and value (1 to 256; CloudFormation rejects an empty value) and their character set (letters, digits, spaces, and `_ . : / = + - @`), as `aws.modules.resource-groups` does, so a bad tag fails at plan instead of apply. Previously only the count and the `aws:` prefix were checked.
- `stack-set`: `CAPABILITY_AUTO_EXPAND` is no longer refused for service-managed StackSets. `CreateStackSet` accepts the capability for them; what fails is a template that references a macro or transform, which the module cannot detect. The precondition blocked a harmless setting without catching the real failure. The README now documents the actual limit.

### Changed

- **`on_failure` defaults to `null` and is ignored after create** (`lifecycle { ignore_changes = [on_failure] }`). In 1.0.0 it was non-nullable with default `"ROLLBACK"` and always sent. The provider never reads it back, so importing an existing stack planned a forced replacement. Now an import plans no change for any value. Unset, nothing is sent and CloudFormation applies its own default, `ROLLBACK`, so creation behaves exactly as before. Upgrade impact: none. A stack created by 1.0.0 (`on_failure = "ROLLBACK"` in state) plans no change, and editing `on_failure` on an existing stack no longer replaces it; the new value takes effect the next time the stack is created. Verified with real plans against provider 6.67.0 (see `docs/DESIGN.md` D11).

## [1.0.0] - 2026-10-05

Initial release.

### Added

- Root module: one `aws_cloudformation_stack` per call, with `name`, `template` (`{ body }` or `{ url }`, exactly one), `parameters`, `capabilities`, `on_failure`, `timeout_in_minutes`, `notification_arns`, `stack_policy` (`{ body }` or `{ url }`, exactly one, optional), `iam_role_arn`, `tags`, and `timeouts`; outputs `id`, `arn`, `name`, and `outputs` (the stack's CloudFormation Outputs).
- Submodule `stack-set`: one `aws_cloudformation_stack_set` and one `aws_cloudformation_stack_set_instance` per `stack_instances` key `"<account_id|ou_id|root_id>/<region>"`, with a two-branch `permission_model` (`self_managed` or `service_managed`), `operation_preferences` applied to the StackSet and its instances where each field applies, `managed_execution_active` (default `true`), per-instance `parameter_overrides` and `retain_stack`, and outputs `id`, `arn`, `name`, `permission_model`, and `stack_instances`.
- Plan-time validation of every client-checkable CloudFormation rule: stack and StackSet name format, the body-or-URL choices, template body (51,200) and stack policy (16,384) sizes in UTF-8 bytes, S3 template and policy URLs, the capability names, parameter count, names, and value size, notification topic count and ARNs, IAM role ARNs and names, the 50-tag limit including the module's `Name`, OU, root, account, and region formats, operation preference ranges and exclusive pairs, and Go durations for timeouts.
- Preconditions on the StackSet: instance targets must match the permission model, and `CAPABILITY_AUTO_EXPAND` is refused for service-managed StackSets.
- Advisory checks: `service_role_not_set` (root), `no_stack_instances` and `max_concurrency_capped_by_failure_tolerance` (stack-set).
- Contract tests with `mock_provider` for the root and the submodule, covering every validation and precondition, both permission models, and every output in apply mode.
- Credential-driven integration suite `smoke` (`make integration-smoke`, dispatch-only `integration` workflow) that creates, updates, and deletes a zero-cost stack, with the IAM trust and permissions documents its role needs.
- Examples: `inline-template`, `s3-template-url`, `stack-set-organization`.
- `docs/DESIGN.md` (why the module exists, decisions, failure-mode analysis, quotas, deferred items), README failure-mode documentation for `ROLLBACK_COMPLETE` and StackSet rollouts, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`, and repository standards (`Makefile`, pre-commit, tflint, terraform-docs, Checkov, Trivy, Dependabot, issue and pull request templates, CODEOWNERS, and a per-directory CI quality matrix).

[Unreleased]: https://github.com/hatan4ik/aws.modules.cloudformation/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/hatan4ik/aws.modules.cloudformation/releases/tag/v1.0.0
