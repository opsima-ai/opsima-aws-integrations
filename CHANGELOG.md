# Changelog

All notable changes to this repository are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Terraform
- `opsima-remote-access` and `opsima-remote-access-iam`: new optional input `opsima_invoice_unit_arn`.
  When set, `OpsimaRemoteAccessRole` loses `invoicing:CreateInvoiceUnit` and `invoicing:TagResource`,
  and `invoicing:GetInvoiceUnit` / `invoicing:UpdateInvoiceUnit` are limited to that Invoice Unit.
  Left empty (the default), Opsima creates the Invoice Unit at onboarding.
- `opsima-remote-access`: new inputs `lambda_timeout` (default 300), `lambda_reserved_concurrency` (default -1,
  no reservation) and `lambda_maximum_retry_attempts` (default 0).

### SCP
- `opsima-scp-linked-accounts.json`: `AcceptHandshake` is denied on any handshake not issued by the Opsima
  Organization, and `ListHandshakesForAccount`, `AcceptHandshake` and `LeaveOrganization` are denied to any
  principal other than `OpsimaOrganizationAccountAccessRole`. A dedicated account can only leave towards Opsima.

## [11.0.1]

### Lambda
- `INVITE`: the session policy used to accept the invitation now also allows
  `organizations:LeaveOrganization` (restricted to the Opsima Organization with `aws:PrincipalOrgID`) and
  `iam:CreateServiceLinkedRole` for `organizations.amazonaws.com` on the invited account's
  `AWSServiceRoleForOrganizations`. AWS checks both permissions inside `AcceptHandshake` when the invited
  account is already a member of an Organization, even though no `LeaveOrganization` call is made and
  the service-linked role already exists.

### SCP
- `opsima-scp-linked-accounts.json`: allows `organizations:LeaveOrganization` and
  `iam:CreateServiceLinkedRole` for `organizations.amazonaws.com`, for the same reason.

## [11.0.0]

First public release. Compared with the previously distributed package:

### Lambda
- `INVITE` now performs the whole transfer in one invocation: it assumes the transferred account's Opsima
  role under a restrictive session policy, verifies the account is a member of the Opsima Organization,
  invites it, accepts the invitation on its behalf and moves it into the Opsima OU. No callback to Opsima.
- The account ID is validated, the root ID comes from the `ORGANIZATION_ROOT_ID` variable,
  creation is polled for up to 4 minutes and the move is retried with backoff. The `MOVE` action is removed.
- Runtime `nodejs24.x`, function timeout 300 s, log group with 365-day retention.

### IAM
- `OpsimaRemoteAccessRole` no longer holds any Organizations write permission; its trust policy requires
  the Opsima platform role (`aws:PrincipalArn`) in addition to the external ID; `sts:AssumeRole` on the
  dedicated accounts' role is limited to members of the customer's Organization (`aws:ResourceOrgID`).
- The Lambda execution role: `CreateAccount` and `InviteAccountToOrganization` require the `owner=opsima`
  request tag; `TagResource` requires `owner=opsima` and `role=OpsimaOrganizationAccountAccessRole` and no
  other key; `MoveAccount` is limited to accounts tagged `owner=opsima` between the root and the Opsima OU;
  `sts:AssumeRole` on the dedicated accounts' role is limited to members of the Opsima Organization.
- Lambda trust policy conditioned on `aws:SourceAccount` and `aws:SourceArn`.

### SCP
- `iam:GetRole` and `iam:UpdateAssumeRolePolicy` removed: the trust policy of the dedicated accounts' role
  is never modified while an account is a member of the customer's Organization.

### CUR bucket
- Public access block, bucket-owner-enforced ownership, 1130-day expiration, `aws:SourceArn` condition.

### Terraform
- Published as modules with `variables.tf`; the Lambda is deployed from a local file (`lambda_filename`),
  built from the tag or downloaded from the GitHub Release.
