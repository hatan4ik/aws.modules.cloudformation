# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

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
