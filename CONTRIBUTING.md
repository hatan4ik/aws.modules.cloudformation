# Contributing

Thank you for improving `aws.modules.cloudformation`. This guide covers the toolchain, the local quality gate, how features are tested and where they belong, commit and pull request conventions, and how releases are cut.

## Development setup

The module targets Terraform `>= 1.7.0, < 2.0.0` and is developed against 1.7.5, the version the consuming platform pins. Install the toolchain:

| Tool | Purpose | Install |
| --- | --- | --- |
| [tfenv](https://github.com/tfutils/tfenv) | Pin the Terraform version | `tfenv install 1.7.5 && tfenv use 1.7.5` |
| [tflint](https://github.com/terraform-linters/tflint) | Lint with the Terraform and AWS rulesets configured in `.tflint.hcl` | `brew install tflint && tflint --init` |
| [terraform-docs](https://terraform-docs.io) v0.20.0 | Generate the inputs and outputs tables in every README. Pinned to the version bundled by the CI docs action; newer releases change table formatting and fail the drift check (`make docs` refuses other versions). | Download the v0.20.0 binary from the [releases page](https://github.com/terraform-docs/terraform-docs/releases/tag/v0.20.0) |
| [checkov](https://www.checkov.io) | Static security policy | `pip install checkov` |
| [trivy](https://trivy.dev) | Misconfiguration scanning | `brew install trivy` |
| [pre-commit](https://pre-commit.com) | Run the gate on every commit | `pip install pre-commit && pre-commit install` |

Clone, initialise without a backend, and run the gate once to confirm the setup:

```sh
terraform init -backend=false -input=false
make check
```

## Integration suites

`tests/integration/` holds credential-driven suites that apply the module for real and destroy everything afterwards. They are never part of `make check` or the quality pipeline. Run them against your own account before a release that touches resource behaviour:

```bash
export AWS_PROFILE=<profile> AWS_REGION=<region>
make integration-smoke   # about a minute; one zero-cost stack, created, updated, and deleted
```

Add a suite when a feature's correctness depends on the AWS API rather than on rendering (for example how the provider reads parameters or outputs back). Keep every value derived from the environment or from disposable fixtures the suite creates, and never reference a real account, OU, bucket, or role. A suite that needs fixtures keeps them in `tests/integration/setup`, which the policy scans exclude.

## The local gate

`make check` is the default target and the same gate CI runs. It stops at the first failing target and must pass before you open a pull request.

| Target | What it runs |
| --- | --- |
| `make fmt` | `terraform fmt -check -recursive -diff` from the repository root. `make fmt-fix` rewrites the files instead. |
| `make validate` | `make init` (`terraform init -backend=false`) followed by `terraform validate` in the root, `modules/stack-set`, `modules/self-managed-roles`, `modules/service-role`, and every example directory. |
| `make lint` | `tflint --init` and then `tflint` in every directory with the root `.tflint.hcl`: documented and typed variables, documented outputs, snake_case naming, no unused declarations, pinned required versions and providers. |
| `make test` | `terraform test` in the root, `modules/stack-set`, `modules/self-managed-roles`, `modules/service-role`, and every example that has a `tests/` directory (`examples/self-managed-bootstrap`, `examples/scoped-service-role`). No credentials are needed. |
| `make lock` | Refresh the committed root `.terraform.lock.hcl` with hashes for linux and macOS on amd64 and arm64 after changing the provider constraint. CI runs `terraform init` before the docs drift check, so a lock file missing the Linux hash gets rewritten and fails that check. |
| `make docs` | `terraform-docs -c .terraform-docs.yml` in every directory, regenerating the tables between the `BEGIN_TF_DOCS` and `END_TF_DOCS` markers. Run it after touching any variable or output. |
| `make docs-check` | The same in `--output-check` mode: fails when a README is out of date. This is the variant `make check` and CI run. |
| `make security` | `checkov -d . --framework terraform`, and `trivy config --severity HIGH,CRITICAL` when trivy is on the PATH. A skip needs an inline `checkov:skip=` comment with a reason on the resource it concerns; the only ones are on `modules/self-managed-roles`' `execution_cloudformation` policy (`cloudformation:*` on `*` is the minimum AWS documents for a StackSets execution role). |
| `make check` | `fmt`, `validate`, `lint`, `test`, `docs-check`, `security`, in that order. |

## Test-first workflow

Every behaviour in this module is pinned by a test before it is implemented. Write the failing `run` block first, then the code, then run `make test`.

- Tests live in `tests/*.tftest.hcl` for the root (`defaults`, `validation`, `checks`, `template_checks`, `on_failure`, `outputs`) and in `modules/stack-set/tests/*.tftest.hcl` for the submodule (`self_managed`, `service_managed`, `operation_preferences`, `validation`, `checks`, `template_checks`, `outputs_self_managed`, `outputs_service_managed`), in `modules/self-managed-roles/tests/*.tftest.hcl` (`administration`, `execution`, `validation`, `checks`, `outputs_administration`, `outputs_execution`), in `modules/service-role/tests/*.tftest.hcl` (`role`, `pass_role`, `validation`, `checks`, `outputs`), and in `examples/self-managed-bootstrap/tests/` and `examples/scoped-service-role/tests/` (`wiring`, providers mocked). Each file starts with `mock_provider "aws" {}` and a `variables` block holding a valid baseline; each `run` overrides only what it exercises.
- Use `command = plan`, except for output tests: stack IDs, ARNs, Outputs, and instance summaries are computed, so the `outputs*` files use `command = apply` with `override_resource`, each in its own file because runs in one file share state.
- Validations are tested with `expect_failures`. Point it at the object that carries the check: `[var.template]` for a variable validation, `[aws_cloudformation_stack_set.this]` for a precondition, `[check.service_role_not_set]` for a `check` block. A run with `expect_failures` passes only if exactly those objects fail; add a positive run alongside so the happy path is covered too. Runs in the root's baseline set `iam_role_arn` so the advisory check stays quiet; a run that unsets it must expect the check.
- Assertions must not depend on unknown values. Under a mock provider, computed attributes are unknown at plan time, including optional-and-computed arguments the module leaves null (`execution_role_name` on a service-managed StackSet, `template_body` when a URL is used). Assert on what the module sends.
- `||` and `&&` do not short-circuit in Terraform 1.7. Both operands are always evaluated, so `var.x == null || var.x.field > 0` fails when `x` is null. Guard with a conditional instead: `var.x == null ? true : var.x.field > 0`. This applies to validations, preconditions, and test assertions alike.
- Keep assertion `error_message` text a statement of the guaranteed behaviour. It becomes the documentation of the contract when a test fails.

## Where to add a feature

| Concern | Lives in |
| --- | --- |
| A stack argument | `variables.tf` with a description, type, and validation; `stack.tf` to render it; a run in `tests/defaults.tftest.hcl` and an `expect_failures` run in `tests/validation.tftest.hcl`. |
| A StackSet or instance argument | `modules/stack-set/variables.tf`; `modules/stack-set/main.tf`; a model-specific input goes inside its `permission_model` branch, never beside it; tests in the matching submodule file. |
| A rule that spans variables | A precondition on `aws_cloudformation_stack_set.this` (or `aws_cloudformation_stack.this`) that names every offending value, or a `check` block when the configuration is valid but usually unintended. |
| A shared contract (template, parameters, capabilities, tags) | Both `variables.tf` files, identically, with tests in both. The two interfaces must not drift. |
| Outputs | `outputs.tf`; every output has a description and an assertion in the apply-mode output tests. |

Rules that apply everywhere: no data sources, no IAM resources, no `type = any`, every variable has a description, a type, `nullable = false` unless `null` has a documented meaning, and a validation where a wrong value would otherwise fail at apply time, and defaults are the API's or a safer one. Before adding an input, check it maps to a real CloudFormation capability and is in scope (see [docs/DESIGN.md, Deferred to v2](docs/DESIGN.md#deferred-to-v2)).

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). The scope is the file or concern the change touches.

```text
feat(stack-set): accept account filters on OU instances
fix(stack): count template size in bytes
docs: explain recovering a failed StackSet update
test(stack-set): cover delegated admin on instances
feat!: key stack_instances by target and region
```

Append `!` after the type or scope for a breaking change and add a `BREAKING CHANGE:` footer explaining what consumers must do. Breaking changes ship only in a major release with an entry in the upgrade guide.

## Pull request checklist

- [ ] `make check` passes locally.
- [ ] New behaviour has a test; changed validations have both a passing and an `expect_failures` run.
- [ ] Variables and outputs have descriptions; `make docs` regenerated the README tables.
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]` in the right category.
- [ ] Breaking changes carry `!`, a `BREAKING CHANGE:` footer, and an update to `docs/UPGRADE-<major>.md`.
- [ ] Examples still initialise and validate; a new feature worth showing has an example.
- [ ] No data sources, no hard-coded account, region, or partition, no new defaults that weaken security.
- [ ] A change to the shared template, parameter, capability, or tag contract is made in both the root and `modules/stack-set`.

## Release process

Releases are cut by maintainers.

1. Move the `## [Unreleased]` entries in `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading, add its compare link, and merge that change to `main`.
2. Create a signed annotated tag on the merge commit. The signing key must be registered with GitHub so the tag shows as Verified:

   ```sh
   git tag -s vX.Y.Z -m "aws.modules.cloudformation vX.Y.Z"
   git push origin vX.Y.Z
   ```

3. Dispatch the `module-release` workflow (`.github/workflows/module-release.yml`) from the tag with `release_tag = vX.Y.Z`: `gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z`. It verifies the signed tag, formatting, validation, tests, and generated docs, then publishes the GitHub release. Never dispatch it from `main`: the workflow checks that the tag points at the revision it checked out, and a maintenance release of an older line is cut from that line's commit.
4. Announce the release with the commit SHA. Consumers pin that SHA, not the tag:

   ```hcl
   source = "git::https://github.com/hatan4ik/aws.modules.cloudformation.git?ref=<commit-sha>" # vX.Y.Z
   ```

Tags are never moved or deleted once published. A bad release is followed by a new patch release.
