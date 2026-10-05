# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.x | Yes. Security fixes and functional fixes on the latest minor release. |
| Unreleased `main` | Not supported for production use. |

## Reporting a vulnerability

Use GitHub private vulnerability reporting on this repository: open the Security tab and choose "Report a vulnerability". Do not open a public issue, pull request, or discussion for a security problem.

Include the module version or commit SHA, the inputs that reproduce the problem, the resulting plan, and the impact you see. Redact account IDs, OU IDs, role ARNs, template URLs, and parameter values.

## What counts

- A module default that weakens security: a capability acknowledged without the caller listing it, a StackSet rollout faster than the CloudFormation defaults without the caller asking for it, a role the caller did not name.
- A validation bypass: an input the module claims to reject at plan time but that reaches the provider (a second template source, a capability outside the three CloudFormation values, a permission-model input in the other model's branch, an instance target of the wrong kind).
- A tag precedence bug: the module's `Name` overriding a caller's tag.
- Sensitive data exposure caused by the module itself, beyond what CloudFormation parameters inherently carry (they are documented as not secret).
- A dependency problem in the release pipeline that could publish unverified code.

Findings in your own inputs (for example a template that grants broad IAM permissions, or secrets passed as parameters against the documentation) or in AWS services themselves are out of scope here; report the latter to AWS.

## Response

We acknowledge a report within 5 business days and keep you informed while we confirm, fix, and release. A fix ships as a patch release of every supported line with a `CHANGELOG.md` entry that credits the reporter unless they ask otherwise. Please give us a reasonable window before disclosing publicly.

## Security design

CloudFormation is an escape hatch on this platform, so the module keeps its use explicit: no capability unless listed, an advisory check while a stack runs without a service role, self-managed StackSet roles always sent, the slowest StackSet rollout unless widened deliberately, caller tags winning over the module's `Name`, no data sources, and no IAM resources. Every claim is enforced by a validation, a precondition, or a `check` block with a `terraform test` case behind it. The full description is in the [Security model](README.md#security-model) section of the README, and the reasoning in [docs/DESIGN.md](docs/DESIGN.md).
