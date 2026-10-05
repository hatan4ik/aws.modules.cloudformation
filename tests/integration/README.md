# Integration suites

The suites in this directory apply the module for real in **your** AWS account
and destroy everything afterwards. They complement the contract tests in
`tests/` and `modules/stack-set/tests/`, which run with `mock_provider`, need
no credentials, and use the AWS documentation account `123456789012`: they
prove the module's interface and rendering, not that AWS accepts it. These
suites prove the latter.

Nothing here is tied to an account, region, or landing zone. Credentials and
the region come from the environment. The stack under test contains a single
`AWS::CloudFormation::WaitConditionHandle`, a placeholder resource that
provisions nothing and costs nothing, so the suite needs no fixtures and
leaves nothing behind. A suite that ever needs fixtures keeps them in
`setup/`, which the policy scans exclude (`.checkov.yml`, `trivy.yaml`).

| Suite | What it proves | Needs | Typical time |
| --- | --- | --- | --- |
| `smoke.tftest.hcl` | The root module creates a stack from an inline template; `arn` and `id` are the real stack ARN; `outputs` carries the stack's real Outputs; an undeclared parameter left to its template `Default` stays out of state (no diff); the `Name` tag and caller tags survive the API; a parameter change updates the stack in place and refreshes `outputs`. | credentials, region | about a minute |

There is no StackSet suite. A meaningful one needs either AWS Organizations
trusted access (service-managed) or administration and execution roles in a
second account (self-managed), which is landing-zone infrastructure, not a
disposable fixture. `modules/stack-set` is covered by its contract tests; see
`docs/DESIGN.md`, Testing strategy.

## Run it in your account

```bash
export AWS_PROFILE=<your profile>   # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
export AWS_REGION=<region>
make integration-smoke              # terraform init -test-directory=tests/integration && terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl
```

The credentials need the permissions in
[`iam/integration-permissions-policy.json`](iam/integration-permissions-policy.json)
(replace `<ACCOUNT_ID>`): the CloudFormation actions to create, read, update,
tag, and delete stacks named `cfn-module-it-*`. The template creates no other
resource, so no other service is touched.

`terraform test` runs `tests/` only by default, so this suite never runs in
the credential-free quality pipeline.

## Run it from GitHub Actions (owner lane)

The `integration` workflow (`.github/workflows/integration.yml`) is
dispatch-only and assumes a role through GitHub OIDC. It reads everything
account-specific from the protected `integration` environment of the
repository, so the code stays universal:

| Environment variable | Meaning |
| --- | --- |
| `AWS_INTEGRATION_ROLE_ARN` | Role the workflow assumes. Trust policy: [`iam/github-oidc-trust-policy.json`](iam/github-oidc-trust-policy.json) with `<OWNER>/<REPO>` set to this repository; permissions: the policy above. |
| `AWS_INTEGRATION_REGION` | Region the stack is created in. |

Dispatch with `gh workflow run integration.yml -f suite=smoke`. Protect the
environment with required reviewers so a run cannot be started from a pull
request by anyone with write access.
