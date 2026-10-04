# Security policy

The resources in this repository are deployed inside customers' AWS Organizations, so we treat every
report seriously.

## Reporting a vulnerability

Email **security@opsima.ai** with a description of the issue, the affected file or version, and, if
possible, steps to reproduce. Please do not open a public issue for security matters.

We acknowledge reports within 2 business days and keep you informed until the issue is resolved. Fixes
are published as a new tagged release, with the change described in the changelog.

## Scope

- Terraform modules and CloudFormation templates in this repository
- The `HandleOpsimaAccounts` Lambda function source
- The service control policy in `scp/`

Opsima's security documentation, including sub-processors, is available at https://trust.opsima.ai.
