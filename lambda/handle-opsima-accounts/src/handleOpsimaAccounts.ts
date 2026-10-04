import {
  OrganizationsClient,
  CreateAccountCommand,
  DescribeCreateAccountStatusCommand,
  MoveAccountCommand,
  InviteAccountToOrganizationCommand,
  AcceptHandshakeCommand,
  DescribeOrganizationCommand,
  HandshakePartyType,
} from "@aws-sdk/client-organizations";
import { STSClient, AssumeRoleCommand, GetCallerIdentityCommand } from "@aws-sdk/client-sts";

type CreateInput = {
  action: "CREATE";
  accountName: string;
  accountEmail: string;
};

type InviteInput = {
  action: "INVITE";
  accountId: string;
};

type HealthCheckInput = {
  action: "HEALTHCHECK";
};

type Input = CreateInput | InviteInput | HealthCheckInput;

type LambdaResponse = {
  statusCode: number;
  body: string;
};

const ROLE_NAME = "OpsimaOrganizationAccountAccessRole";
const OPSIMA_OU_ID = process.env.OPSIMA_OU_ID!;
const ORGANIZATION_ROOT_ID = process.env.ORGANIZATION_ROOT_ID!;
// Identity of the Opsima Organization an invited account must come from. Set by the customer's stack.
const OPSIMA_ORGANIZATION_ID = process.env.OPSIMA_ORGANIZATION_ID!;
const OPSIMA_MANAGEMENT_ACCOUNT_ID = process.env.OPSIMA_MANAGEMENT_ACCOUNT_ID!;
// This organization (the one the Lambda runs in). Set by the customer's stack.
const ORGANIZATION_ID = process.env.ORGANIZATION_ID!;
const ASSUME_ROLE_DURATION_SECONDS = 900; // STS minimum
const ACCOUNT_ID_PATTERN = /^[0-9]{12}$/;

const org = new OrganizationsClient({});
const sts = new STSClient({});

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function waitForAccountCreation(createRequestId: string): Promise<string> {
  // Account creation usually takes seconds but can take several minutes: poll for up to 4 minutes.
  const maxAttempts = 48;
  const delayMs = 5000;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const status = await org.send(
      new DescribeCreateAccountStatusCommand({ CreateAccountRequestId: createRequestId })
    );

    const s = status.CreateAccountStatus;
    if (!s) {
      throw new Error("CreateAccountStatus missing");
    }

    if (s.State === "SUCCEEDED") {
      if (!s.AccountId) {
        throw new Error("AccountId missing after successful creation");
      }
      return s.AccountId;
    }

    if (s.State === "FAILED") {
      throw new Error(`CreateAccount failed: ${s.FailureReason ?? "UNKNOWN"}`);
    }

    await sleep(delayMs);
  }

  throw new Error("Timed out waiting for account creation");
}

async function moveAccountToOrganizationalUnit(
  accountId: string,
): Promise<void> {
  // 5 attempts with exponential backoff (2, 4, 8, 16 s): membership and tags can take a few
  // seconds to propagate right after creation or acceptance.
  const maxAttempts = 5;
  const initialDelayMs = 2000;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await org.send(
        new MoveAccountCommand({
          AccountId: accountId,
          SourceParentId: ORGANIZATION_ROOT_ID,
          DestinationParentId: OPSIMA_OU_ID,
        })
      );
      return;
    } catch (err) {
      if (attempt === maxAttempts) {
        throw err;
      }
      await sleep(initialDelayMs * 2 ** (attempt - 1));
    }
  }
}

function getManagementAccountId(context: any): string {
  // arn:aws:lambda:<region>:<account-id>:function:<name>
  const accountId = String(context?.invokedFunctionArn ?? "").split(":")[4];
  if (!ACCOUNT_ID_PATTERN.test(accountId)) {
    throw new Error("Unable to determine the management account ID from the invocation context");
  }
  return accountId;
}

/**
 * Session policy applied to the role assumed in the invited account. The session can only:
 * - prove which organization the account currently belongs to,
 * - accept an invitation issued by THIS organization.
 * Everything else the role could do (AdministratorAccess) is denied for this session.
 */
function buildAcceptInvitationSessionPolicy(managementAccountId: string): string {
  return JSON.stringify({
    Version: "2012-10-17",
    Statement: [
      {
        Sid: "ProveCurrentOrganization",
        Effect: "Allow",
        Action: "organizations:DescribeOrganization",
        Resource: "*",
      },
      {
        Sid: "AcceptInvitationFromThisOrganizationOnly",
        Effect: "Allow",
        Action: "organizations:AcceptHandshake",
        Resource: `arn:aws:organizations::${managementAccountId}:handshake/${ORGANIZATION_ID}/invite/*`,
      },
    ],
  });
}

/**
 * Assumes the Opsima role inside the invited account, with the restrictive session policy above.
 * Succeeding here already proves that the role's trust policy has been handed over to this
 * management account before the invitation.
 */
async function assumeInvitedAccountRole(accountId: string, managementAccountId: string) {
  const { Credentials } = await sts.send(
    new AssumeRoleCommand({
      RoleArn: `arn:aws:iam::${accountId}:role/${ROLE_NAME}`,
      RoleSessionName: "opsima-accept-invitation",
      DurationSeconds: ASSUME_ROLE_DURATION_SECONDS,
      Policy: buildAcceptInvitationSessionPolicy(managementAccountId),
    })
  );

  if (!Credentials?.AccessKeyId || !Credentials.SecretAccessKey || !Credentials.SessionToken) {
    throw new Error(`AssumeRole on ${ROLE_NAME} in account ${accountId} returned no credentials`);
  }

  return {
    accessKeyId: Credentials.AccessKeyId,
    secretAccessKey: Credentials.SecretAccessKey,
    sessionToken: Credentials.SessionToken,
  };
}

/**
 * Verifies, with the invited account's own credentials, that:
 * 1. the credentials belong to the invited account and to the Opsima role,
 * 2. the account is currently a member of the Opsima Organization (hence went through Opsima's quarantine).
 */
async function verifyInvitedAccount(
  accountId: string,
  credentials: { accessKeyId: string; secretAccessKey: string; sessionToken: string },
): Promise<void> {
  const identity = await new STSClient({ credentials }).send(new GetCallerIdentityCommand({}));
  if (identity.Account !== accountId) {
    throw new Error(`Credentials belong to account ${identity.Account}, expected ${accountId}`);
  }
  if (!identity.Arn?.includes(`:assumed-role/${ROLE_NAME}/`)) {
    throw new Error(`Credentials are not a session of ${ROLE_NAME}: ${identity.Arn}`);
  }

  const { Organization } = await new OrganizationsClient({ credentials }).send(
    new DescribeOrganizationCommand({})
  );
  if (
    Organization?.Id !== OPSIMA_ORGANIZATION_ID ||
    Organization?.MasterAccountId !== OPSIMA_MANAGEMENT_ACCOUNT_ID
  ) {
    throw new Error(
      `Account ${accountId} is not a member of the Opsima Organization (found ${Organization?.Id ?? "none"}, management account ${Organization?.MasterAccountId ?? "none"})`
    );
  }
}

async function acceptInvitationAsInvitedAccount(
  handshakeId: string,
  credentials: { accessKeyId: string; secretAccessKey: string; sessionToken: string },
): Promise<void> {
  await new OrganizationsClient({ credentials }).send(
    new AcceptHandshakeCommand({ HandshakeId: handshakeId })
  );
}

function ok(body: unknown): LambdaResponse {
  return { statusCode: 200, body: JSON.stringify(body) };
}

function badRequest(message: string): LambdaResponse {
  return { statusCode: 400, body: JSON.stringify({ error: message }) };
}

function serverError(message: string, details?: unknown): LambdaResponse {
  return { statusCode: 500, body: JSON.stringify({ error: message, details }) };
}

function parseInput(event: any): Input {
  return typeof event?.body === "string" ? JSON.parse(event.body) : (event ?? {});
}

export const handler = async (event: any, context: any): Promise<LambdaResponse> => {
  try {
    const input: Input = parseInput(event);

    if (!input?.action) {
      return badRequest('Missing "action"');
    }

    if (input.action === "CREATE") {
      const { accountName, accountEmail } = input;

      if (!accountName || !accountEmail) {
        return badRequest("Missing required fields: accountName, accountEmail");
      }

      if (!accountName.startsWith("ocm+")) {
        return badRequest(`accountName must start with "ocm+"`);
      }

      const createOut = await org.send(
        new CreateAccountCommand({
          AccountName: accountName,
          Email: accountEmail,
          RoleName: ROLE_NAME,
          IamUserAccessToBilling: "ALLOW",
          Tags: [
            { Key: "owner", Value: "opsima" },
            { Key: "role", Value: ROLE_NAME },
          ],
        })
      );

      const createRequestId = createOut.CreateAccountStatus?.Id;
      if (!createRequestId) {
        throw new Error("CreateAccountRequestId missing");
      }

      const accountId = await waitForAccountCreation(createRequestId);

      await moveAccountToOrganizationalUnit(accountId);

      return ok({
        ok: true,
        action: "CREATE",
        accountId,
        accountName,
        destinationOuId: OPSIMA_OU_ID,
      });
    }

    if (input.action === "INVITE") {
      const { accountId } = input;

      if (!accountId) {
        return badRequest("Missing required field: accountId");
      }

      if (!ACCOUNT_ID_PATTERN.test(accountId)) {
        return badRequest("accountId must be a 12-digit AWS account ID");
      }

      const managementAccountId = getManagementAccountId(context);

      // Assume the Opsima role in the invited account BEFORE inviting: if this fails, the trust
      // policy has not been handed over to this organization and nothing is created.
      const invitedAccountCredentials = await assumeInvitedAccountRole(accountId, managementAccountId);
      await verifyInvitedAccount(accountId, invitedAccountCredentials);

      const res = await org.send(
        new InviteAccountToOrganizationCommand({
          Target: {
            Type: HandshakePartyType.ACCOUNT,
            Id: accountId,
          },
          Tags: [
            { Key: "owner", Value: "opsima" },
            { Key: "role", Value: ROLE_NAME },
          ],
        })
      );

      const handshakeId = res.Handshake?.Id;
      if (!handshakeId) {
        throw new Error("HandshakeId missing");
      }

      await acceptInvitationAsInvitedAccount(handshakeId, invitedAccountCredentials);

      await moveAccountToOrganizationalUnit(accountId);

      return ok({
        ok: true,
        action: "INVITE",
        accountId
      });
    }

    if (input.action === "HEALTHCHECK") {
      return ok({
        ok: true,
        action: "HEALTHCHECK",
      });
    }

    return badRequest("Unknown action. Valid actions: CREATE, INVITE, HEALTHCHECK");
  } catch (err: any) {
    return serverError("Unhandled error", {
      name: err?.name,
      message: err?.message,
    });
  }
};
