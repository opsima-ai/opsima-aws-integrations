# Security controls

## Service control policy

`scp/opsima-scp-linked-accounts.json` is attached by you to the Opsima OU. It denies every action except
Savings Plans and Reserved Instances operations, `account:PutContactInformation`, the ElastiCache
service-linked role creation, and `organizations:ListHandshakesForAccount` / `AcceptHandshake`, which a
transfer out needs. Removing `AcceptHandshake` from the SCP prevents any account from leaving your
Organization. The SCP applies to every principal in the dedicated accounts, including the root user.

Consider attaching it, or creating the OU, before deploying the Opsima package: the OU can be provided
through `opsima_organizational_unit_id`, so that no Opsima access exists before the OU is governed. A
root-level statement applying the same allow-list to the principal
`arn:aws:iam::*:role/OpsimaOrganizationAccountAccessRole` also covers the seconds an account spends at the
root before being moved.

## Trust policies

- `OpsimaRemoteAccessRole` can only be assumed by Opsima's platform role, presenting your external ID.
- The Lambda execution role can only be assumed by the Lambda service on behalf of the
  `HandleOpsimaAccounts` function of your account (`aws:SourceAccount`, `aws:SourceArn`).
- The trust policy of the dedicated accounts' role cannot be modified inside your Organization.

## Organization boundaries

`sts:AssumeRole` on `OpsimaOrganizationAccountAccessRole` is conditioned on `aws:ResourceOrgID`: your
Organization for `OpsimaRemoteAccessRole`, the Opsima Organization for the Lambda role. The Lambda also
refuses to accept an invitation unless the account is a member of the Opsima Organization.

## Session policy

When the Lambda accepts an invitation on behalf of a transferred account, it assumes that account's role
under a session policy it builds itself, allowing only `organizations:DescribeOrganization` and
`organizations:AcceptHandshake` on handshakes issued by your Organization. The policy is in the function
source you build.

## Root user

Accounts created in an Organization have no root credentials and cannot recover a root password unless
your Management Account allows it. With centralized root access management enabled, you can verify and
delete root credentials on any Opsima account on arrival. Opsima's process never uses the root user.

## Recommended detections

CloudTrail events to forward to your security team: `CreateAccount`, `InviteAccountToOrganization`,
`AcceptHandshake`, `MoveAccount`, `TagResource`, `lambda:InvokeFunction` on `HandleOpsimaAccounts` (a
data event), assumptions of `OpsimaOrganizationAccountAccessRole`, `UpdateAssumeRolePolicy` attempts,
root sign-in in Opsima accounts, and commitment purchases. A periodic check of `owner=opsima` accounts
directly under your root catches any failed move.
