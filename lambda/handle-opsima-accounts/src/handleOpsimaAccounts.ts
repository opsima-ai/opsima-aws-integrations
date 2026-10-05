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

type ActionResult = {
  statusCode: number;
  body: Record<string, unknown>;
};

type InvocationContext = {
  invokedFunctionArn?: string;
};

type SessionCredentials = {
  accessKeyId: string;
  secretAccessKey: string;
  sessionToken: string;
};

const LAMBDA_VERSION = "11.0.0-rc.4";
const ROLE_NAME = "OpsimaOrganizationAccountAccessRole";
const OPSIMA_OU_ID = process.env.OPSIMA_OU_ID!;
const ORGANIZATION_ROOT_ID = process.env.ORGANIZATION_ROOT_ID!;
const OPSIMA_ORGANIZATION_ID = process.env.OPSIMA_ORGANIZATION_ID!;
const OPSIMA_MANAGEMENT_ACCOUNT_ID = process.env.OPSIMA_MANAGEMENT_ACCOUNT_ID!;
const ORGANIZATION_ID = process.env.ORGANIZATION_ID!;
const ASSUME_ROLE_DURATION_SECONDS = 900; // STS minimum
const ACCOUNT_ID_PATTERN = /^[0-9]{12}$/;
const OPSIMA_ACCOUNT_TAGS = [
  { Key: "owner", Value: "opsima" },
  { Key: "role", Value: ROLE_NAME },
];

const org = new OrganizationsClient({});
const sts = new STSClient({});

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function ok(body: Record<string, unknown>): ActionResult {
  return { statusCode: 200, body };
}

function badRequest(message: string): ActionResult {
  return { statusCode: 400, body: { error: message } };
}

function serverError(message: string, details?: unknown): ActionResult {
  return { statusCode: 500, body: { error: message, details } };
}

function log(level: "info" | "warn" | "error", record: Record<string, unknown>): void {
  console[level](record);
}

/** Returns the identifier an action applies to, for the log record written when it starts. */
function describeTarget(input: Input): Record<string, unknown> {
  const { accountId, accountName } = input as Partial<InviteInput & CreateInput>;

  return {
    ...(typeof accountId === "string" ? { accountId } : {}),
    ...(typeof accountName === "string" ? { accountName } : {}),
  };
}

function describeError(err: unknown): { name?: string; message?: string } {
  if (err instanceof Error) {
    return { name: err.name, message: err.message };
  }

  return { message: String(err) };
}

function parseInput(event: unknown): Input {
  if (event && typeof event === "object" && "body" in event && typeof event.body === "string") {
    return JSON.parse(event.body) as Input;
  }

  return (event ?? {}) as Input;
}

class StepError extends Error {
  constructor(
    readonly step: string,
    cause: unknown,
  ) {
    super(cause instanceof Error ? cause.message : String(cause), { cause });
    this.name = cause instanceof Error ? cause.name : "Error";
  }
}

/** Runs one step of an action and, if it fails, rethrows its error tagged with the step name. */
async function runStep<T>(step: string, action: () => Promise<T>): Promise<T> {
  try {
    return await action();
  } catch (err) {
    throw new StepError(step, err);
  }
}

/**
 * Builds the 500 response of a failed action: the step that failed, the identifiers known at that
 * point, and the name and message of the original error.
 */
function stepFailure(
  action: Input["action"],
  err: unknown,
  context: Record<string, string | undefined>,
): ActionResult {
  const step = err instanceof StepError ? err.step : undefined;

  return serverError(`${action} failed${step ? ` at step ${step}` : ""}`, {
    step,
    ...context,
    ...describeError(err),
  });
}

/**
 * Requests the creation of a dedicated account, tagged as an Opsima account.
 * Returns the ID of the creation request.
 */
async function createAccount(accountName: string, accountEmail: string): Promise<string> {
  const { CreateAccountStatus } = await org.send(
    new CreateAccountCommand({
      AccountName: accountName,
      Email: accountEmail,
      RoleName: ROLE_NAME,
      IamUserAccessToBilling: "ALLOW",
      Tags: OPSIMA_ACCOUNT_TAGS,
    }),
  );

  if (!CreateAccountStatus?.Id) {
    throw new Error("CreateAccountRequestId missing");
  }

  return CreateAccountStatus.Id;
}

/**
 * Polls the status of an account creation request every 5 seconds, for up to 4 minutes.
 * Returns the ID of the new account, or throws if the creation fails or does not complete in time.
 */
async function waitForAccountCreation(createRequestId: string): Promise<string> {
  const maxAttempts = 48;
  const delayMs = 5000;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const status = await org.send(
      new DescribeCreateAccountStatusCommand({ CreateAccountRequestId: createRequestId }),
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

/**
 * Moves an account from the root of this organization into the Opsima OU, where the customer's
 * SCP applies. The only move this function performs is root -> Opsima OU.
 * 5 attempts with exponential backoff (2, 4, 8, 16 s): membership and tags can take a few
 * seconds to propagate right after creation or acceptance.
 */
async function moveAccountToOrganizationalUnit(accountId: string): Promise<void> {
  const maxAttempts = 5;
  const initialDelayMs = 2000;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await org.send(
        new MoveAccountCommand({
          AccountId: accountId,
          SourceParentId: ORGANIZATION_ROOT_ID,
          DestinationParentId: OPSIMA_OU_ID,
        }),
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

/**
 * Returns the ID of the account this function runs in (the customer's Management Account), read
 * from the function ARN of the invocation context. Used to scope the session policy below.
 */
function getManagementAccountId(context: InvocationContext | undefined): string {
  // arn:aws:lambda:<region>:<account-id>:function:<name>
  const accountId = (context?.invokedFunctionArn ?? "").split(":")[4] ?? "";

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
async function assumeInvitedAccountRole(
  accountId: string,
  managementAccountId: string,
): Promise<SessionCredentials> {
  const { Credentials } = await sts.send(
    new AssumeRoleCommand({
      RoleArn: `arn:aws:iam::${accountId}:role/${ROLE_NAME}`,
      RoleSessionName: "opsima-accept-invitation",
      DurationSeconds: ASSUME_ROLE_DURATION_SECONDS,
      Policy: buildAcceptInvitationSessionPolicy(managementAccountId),
    }),
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
 * 2. the account is currently a member of the Opsima Organization (hence went through Opsima's sanitize process).
 */
async function verifyInvitedAccount(
  accountId: string,
  credentials: SessionCredentials,
): Promise<void> {
  const identity = await new STSClient({ credentials }).send(new GetCallerIdentityCommand({}));

  if (identity.Account !== accountId) {
    throw new Error(`Credentials belong to account ${identity.Account}, expected ${accountId}`);
  }

  if (!identity.Arn?.includes(`:assumed-role/${ROLE_NAME}/`)) {
    throw new Error(`Credentials are not a session of ${ROLE_NAME}: ${identity.Arn}`);
  }

  const { Organization } = await new OrganizationsClient({ credentials }).send(
    new DescribeOrganizationCommand({}),
  );

  if (
    Organization?.Id !== OPSIMA_ORGANIZATION_ID ||
    Organization?.MasterAccountId !== OPSIMA_MANAGEMENT_ACCOUNT_ID
  ) {
    throw new Error(
      `Account ${accountId} is not a member of the Opsima Organization (found ${Organization?.Id ?? "none"}, management account ${Organization?.MasterAccountId ?? "none"})`,
    );
  }
}

/**
 * Invites the account into this organization, tagged as an Opsima account.
 * Returns the ID of the invitation handshake.
 */
async function inviteAccount(accountId: string): Promise<string> {
  const { Handshake } = await org.send(
    new InviteAccountToOrganizationCommand({
      Target: {
        Type: HandshakePartyType.ACCOUNT,
        Id: accountId,
      },
      Tags: OPSIMA_ACCOUNT_TAGS,
    }),
  );

  if (!Handshake?.Id) {
    throw new Error("HandshakeId missing");
  }

  return Handshake.Id;
}

/**
 * Accepts the invitation on behalf of the invited account, using the restricted session
 * credentials obtained from assumeInvitedAccountRole. The account joins this organization here.
 */
async function acceptInvitationAsInvitedAccount(
  handshakeId: string,
  credentials: SessionCredentials,
): Promise<void> {
  await new OrganizationsClient({ credentials }).send(
    new AcceptHandshakeCommand({ HandshakeId: handshakeId }),
  );
}

/**
 * CREATE: creates a dedicated account tagged as an Opsima account, waits for its creation and
 * moves it into the Opsima OU.
 */
async function handleCreate(input: CreateInput): Promise<ActionResult> {
  const { accountName, accountEmail } = input;

  if (!accountName || !accountEmail) {
    return badRequest("Missing required fields: accountName, accountEmail");
  }

  if (!accountName.startsWith("ocm+")) {
    return badRequest(`accountName must start with "ocm+"`);
  }

  let accountId: string | undefined;

  try {
    const createRequestId = await runStep("CREATE_ACCOUNT", () =>
      createAccount(accountName, accountEmail),
    );

    const createdAccountId = await runStep("WAIT_FOR_CREATION", () =>
      waitForAccountCreation(createRequestId),
    );

    accountId = createdAccountId;

    await runStep("MOVE_ACCOUNT", () => moveAccountToOrganizationalUnit(createdAccountId));
  } catch (err) {
    return stepFailure("CREATE", err, { accountName, accountId });
  }

  return ok({
    ok: true,
    action: "CREATE",
    accountId,
    accountName,
    destinationOuId: OPSIMA_OU_ID,
  });
}

/**
 * INVITE: transfers an account from the Opsima Organization into this organization. Assumes the
 * account's Opsima role under a restricted session, verifies the account, invites it, accepts the
 * invitation on its behalf and moves it into the Opsima OU.
 */
async function handleInvite(
  input: InviteInput,
  context: InvocationContext | undefined,
): Promise<ActionResult> {
  const { accountId } = input;

  if (!accountId) {
    return badRequest("Missing required field: accountId");
  }

  if (!ACCOUNT_ID_PATTERN.test(accountId)) {
    return badRequest("accountId must be a 12-digit AWS account ID");
  }

  const managementAccountId = getManagementAccountId(context);

  let handshakeId: string | undefined;

  try {
    const invitedAccountCredentials = await runStep("ASSUME_ROLE", () =>
      assumeInvitedAccountRole(accountId, managementAccountId),
    );

    await runStep("VERIFY_ACCOUNT", () =>
      verifyInvitedAccount(accountId, invitedAccountCredentials),
    );

    const invitationHandshakeId = await runStep("INVITE_ACCOUNT", () => inviteAccount(accountId));

    handshakeId = invitationHandshakeId;

    await runStep("ACCEPT_INVITATION", () =>
      acceptInvitationAsInvitedAccount(invitationHandshakeId, invitedAccountCredentials),
    );
    await runStep("MOVE_ACCOUNT", () => moveAccountToOrganizationalUnit(accountId));
  } catch (err) {
    return stepFailure("INVITE", err, { accountId, handshakeId });
  }

  return ok({
    ok: true,
    action: "INVITE",
    accountId,
  });
}

/** HEALTHCHECK: returns the version of the deployed function. */
function handleHealthCheck(): ActionResult {
  return ok({
    ok: true,
    action: "HEALTHCHECK",
    version: LAMBDA_VERSION,
  });
}

/** Runs the handler matching the "action" field of the input. */
async function dispatch(
  input: Input,
  context: InvocationContext | undefined,
): Promise<ActionResult> {
  if (!input.action) {
    return badRequest('Missing "action"');
  }

  switch (input.action) {
    case "CREATE":
      return handleCreate(input);
    case "INVITE":
      return handleInvite(input, context);
    case "HEALTHCHECK":
      return handleHealthCheck();
    default:
      return badRequest("Unknown action. Valid actions: CREATE, INVITE, HEALTHCHECK");
  }
}

/**
 * Entry point. Reads the input, runs the requested action and returns its result. Any unexpected
 * failure is returned as a 500 response carrying the error name and message.
 */
export const handler = async (
  event: unknown,
  context: InvocationContext | undefined,
): Promise<LambdaResponse> => {
  let action: string | undefined;
  let result: ActionResult;

  try {
    const input = parseInput(event);

    action = input.action;

    log("info", { event: "ACTION_STARTED", action, ...describeTarget(input) });

    result = await dispatch(input, context);
  } catch (err: unknown) {
    result = serverError("Unhandled error", describeError(err));
  }

  const { statusCode, body } = result;

  if (statusCode === 200) {
    log("info", { event: "ACTION_SUCCEEDED", statusCode, ...body });
  } else {
    log(statusCode === 400 ? "warn" : "error", {
      event: "ACTION_FAILED",
      action,
      statusCode,
      ...body,
    });
  }

  return { statusCode, body: JSON.stringify(body) };
};
