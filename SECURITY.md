# Security policy

The resources in this repository are deployed inside customers' AWS Organizations, so we treat every
report seriously.

## Reporting a vulnerability

Email **security@opsima.ai** with a description of the issue, the affected file or version, and, if
possible, steps to reproduce. Please do not open a public issue for security matters.

We acknowledge reports within 24 hours and keep you informed until the issue is resolved. Fixes
are published as a new tagged release, with the change described in the changelog.

## Scope

- Terraform modules and CloudFormation templates in this repository
- The `HandleOpsimaAccounts` Lambda function source
- The service control policy in `scp/`

## Supply chain

- Every third-party GitHub Action used by this repository's workflows is pinned to a full commit
  SHA, so a repointed tag cannot alter the build or release pipeline.
- The Lambda package is built from a tagged commit by the release workflow and published as a
  GitHub Release together with its SHA-256 checksum. The same file is copied to Opsima's public
  bucket under a versioned key that is never overwritten.
- Dependabot keeps the pinned actions and the Lambda dependencies up to date.

Opsima's security documentation, including sub-processors, is available at https://trust.opsima.ai.
