#!/usr/bin/env node
// Seed the declared OpenCode Go accounts into OpenCode's own credential store and enable the native
// OpenChamber account switch. This is the only writer besides the UI, and it writes through
// OpenChamber's supported API: OpenCode owns the credentials, OpenChamber owns its settings file,
// and nothing here touches the SQLite store or writes a settings document.
//
// Least privilege: the API keys and the UI password arrive as systemd credentials
// (`LoadCredential`), never as argv, environment values, Nix-store strings or log lines. The
// scripts prints only slot names, counts and credential ids.
//
// Identity and ownership: every account this program owns has the id
// `cred_nixfiles_go_<slot>_<hash12>` and the label `nixfiles: <slot>`. The hash is the first 12 hex
// characters of a salted SHA-256 of the key, so the id changes exactly when the declared key does.
// No other credential is read, removed or activated. In particular a manually connected ChatGPT or
// Console login and the shared `opencode` integration are never touched.
//
// Idempotency: when the desired id already exists, the slot makes no write at all. A rotation
// happens only when the key changed (desired id absent while an owned id for the slot exists):
// create the replacement, keep the previous selection if it was active, then remove the stale rows.
// A retirement moves the selection to a declared replacement before the active row is deleted, so a
// failed activation leaves the old selection intact and the next run can finish the work. At the
// end of a run an integration with no active credential at all is healed from the declaration; an
// active foreign or manually chosen credential is never replaced.
//
// Active state is read from OpenCode's credential table as metadata only (id + active), because the
// client API intentionally refuses a credential list; keys are never selected or copied. The table
// is read exactly where a decision depends on it: the selected row during rotation and retirement,
// and whether the integration is left without any selection.
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const PREFIX = 'cred_nixfiles_go_';
const ID_PATTERN = new RegExp(`^${PREFIX}(.+)_([0-9a-f]{12})$`);

const configPath = process.env.OPENCHAMBER_GO_CONFIG || '/etc/openchamber/go-accounts.json';
const credentialsDir = process.env.CREDENTIALS_DIRECTORY || process.env.OPENCHAMBER_GO_CREDENTIALS_DIR;

const fail = (code, message) => {
  console.error(`openchamber go accounts: ${message}`);
  process.exit(code);
};
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

let config;
try {
  config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch {
  fail(69, `configuration unavailable at ${configPath}`);
}

const server = String(config.serverUrl || '').replace(/\/$/, '');
const integrationID = String(config.integrationID || 'opencode-go');
const switchProvider = String(config.switchProvider || integrationID);
const stateFile = String(config.stateFile || '');
const dbPath = config.opencodeDatabase ? String(config.opencodeDatabase) : '';
const slots = Array.isArray(config.slots) ? config.slots : [];

if (!server || !credentialsDir || !stateFile) fail(69, 'configuration incomplete');

const seen = new Set();
for (const slot of slots) {
  if (!/^[a-z0-9][a-z0-9-]{0,30}$/.test(slot?.slot || '')) fail(65, `invalid slot name ${JSON.stringify(slot?.slot)}`);
  if (!/^[a-z0-9][a-z0-9-]{0,30}$/.test(slot?.secretId || '')) fail(65, `invalid credential id for slot ${slot.slot}`);
  if (seen.has(slot.slot)) fail(65, `duplicate slot ${slot.slot}`);
  seen.add(slot.slot);
}

const readCredential = (id) => {
  try {
    const value = fs.readFileSync(`${credentialsDir}/${id}`, 'utf8').replace(/\r?\n$/, '');
    if (!value || /[\r\n]/.test(value)) fail(69, `credential ${id} is empty or multiline`);
    return value;
  } catch (error) {
    if (error?.code === 'ENOENT') fail(69, `credential ${id} is not staged by systemd`);
    throw error;
  }
};

const saltedHash = (slot, key) =>
  crypto.createHash('sha256').update(`nixfiles-go-accounts\0${slot}\0${key}`).digest('hex');

const password = readCredential('ui_password');
const declared = slots.map((slot) => {
  const key = readCredential(slot.secretId);
  const hash = saltedHash(slot.slot, key);
  return {
    slot: slot.slot,
    key,
    secret: slot.secret || slot.secretId,
    label: `nixfiles: ${slot.slot}`,
    hash,
    id: `${PREFIX}${slot.slot}_${hash.slice(0, 12)}`,
  };
});

const login = async () => {
  for (let attempt = 0; attempt < 90; attempt += 1) {
    try {
      const response = await fetch(`${server}/auth/session`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', accept: 'application/json' },
        body: JSON.stringify({ password }),
        signal: AbortSignal.timeout(10_000),
      });
      if (response.status === 401) fail(77, 'the OpenChamber UI password was rejected');
      const cookie = (response.headers.get('set-cookie') || '').split(';')[0];
      if (response.ok && cookie.startsWith('oc_ui_session')) return cookie;
      await sleep(2_000);
    } catch {
      await sleep(2_000);
    }
  }
  return fail(75, 'the OpenChamber server did not become reachable');
};

const cookie = await login();

const api = async (method, path, body) => {
  let response;
  try {
    response = await fetch(`${server}${path}`, {
      method,
      headers: {
        cookie,
        accept: 'application/json',
        ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(20_000),
    });
  } catch {
    return { status: 0, body: null };
  }
  let parsed = null;
  try {
    parsed = await response.json();
  } catch {
    parsed = null;
  }
  return { status: response.status, body: parsed };
};

const readIntegrations = async () => {
  let answer;
  for (let attempt = 0; attempt < 30; attempt += 1) {
    try {
      answer = await api('GET', '/api/integration');
    } catch {
      answer = null;
    }
    if (answer?.status === 200 && Array.isArray(answer.body?.data)) break;
    // A settings write reloads the managed OpenCode; the catalog can be briefly unavailable.
    await sleep(1_000);
  }
  if (answer?.status !== 200 || !Array.isArray(answer.body?.data)) {
    fail(75, `could not read the integration catalog (HTTP ${answer?.status ?? 'network error'})`);
  }
  const integration = answer.body.data.find((entry) => entry.id === integrationID);
  if (!integration) fail(65, `integration ${integrationID} is not in the catalog`);
  return integration.connections.filter((connection) => connection.type === 'credential');
};

const withDatabase = (read) => {
  if (!dbPath) fail(65, 'opencodeDatabase is required to preserve the active account during rotation');
  let database;
  try {
    database = new DatabaseSync(dbPath, { readOnly: true });
    return read(database);
  } catch (error) {
    fail(65, `could not read credential metadata (${error instanceof Error ? error.message : String(error)})`);
  } finally {
    database?.close?.();
  }
};

const isActive = (credentialID) =>
  Boolean(withDatabase((database) => database.prepare('select active from credential where id = ?').get(credentialID)?.active));

const activeCredentialForIntegration = () => {
  const row = withDatabase((database) =>
    database.prepare('select id from credential where integration_id = ? and active = 1').get(integrationID),
  );
  return row?.id ?? null;
};

const create = async (account) => {
  const answer = await api('POST', '/api/credential', {
    id: account.id,
    integrationID,
    label: account.label,
    value: {
      type: 'key',
      key: account.key,
      metadata: { managedBy: 'nixfiles', slot: account.slot, source: `sops:${account.secret}` },
    },
    activate: false,
  });
  if (answer.status === 200 || answer.status === 201) return answer.body?.data ?? answer.body;
  if (answer.status === 409) return null; // already there; the read below is the truth
  fail(65, `could not create ${account.slot} (HTTP ${answer.status})`);
};

const activate = async (credentialID) => {
  const answer = await api('POST', `/api/credential/${encodeURIComponent(credentialID)}/activate`);
  if (answer.status !== 200 && answer.status !== 204) {
    fail(65, `could not activate ${credentialID} (HTTP ${answer.status})`);
  }
};

const remove = async (credentialID) => {
  const answer = await api('DELETE', `/api/credential/${encodeURIComponent(credentialID)}`);
  if (answer.status !== 200 && answer.status !== 204) {
    fail(65, `could not remove ${credentialID} (HTTP ${answer.status})`);
  }
};

let connections = await readIntegrations();
const owned = () => connections.filter((connection) => connection.id.startsWith(PREFIX));
for (const connection of owned()) {
  if (!ID_PATTERN.test(connection.id)) fail(65, `owned-looking credential ${connection.id} does not match the managed id shape; refusing to guess`);
}

// Create or rotate one slot. Nothing is written when the desired id is already present.
const reconcileSlot = async (account) => {
  const present = new Set(connections.map((connection) => connection.id));
  const stale = connections
    .filter((connection) => {
      const match = ID_PATTERN.exec(connection.id);
      return match?.[1] === account.slot && connection.id !== account.id;
    })
    .map((connection) => connection.id);

  if (present.has(account.id) && stale.length === 0) return 'unchanged';

  const staleActive = stale.some((id) => isActive(id));
  if (!present.has(account.id)) {
    await create(account);
  }
  if (staleActive && !isActive(account.id)) {
    // The replaced row was the selected account. Move the selection to its replacement before the
    // old row disappears; a non-active slot is never activated.
    await activate(account.id);
  }
  for (const id of stale) await remove(id);
  return stale.length > 0 ? 'rotated' : 'created';
};

const outcomes = [];
for (const account of declared) {
  outcomes.push({ slot: account.slot, result: await reconcileSlot(account) });
  connections = await readIntegrations();
}

// Retire owned slots that are no longer declared. If the retired row was the selected account,
// select a declared replacement before deleting it; a failed activation aborts with the old row
// still active. A foreign or manual selection is left untouched, and an empty declaration removes
// the owned rows without activating anything else.
const declaredSlots = new Set(declared.map((account) => account.slot));
for (const connection of owned()) {
  const match = ID_PATTERN.exec(connection.id);
  if (declaredSlots.has(match[1])) continue;
  const wasActive = isActive(connection.id);
  if (wasActive) {
    const replacement = declared.find((account) => connections.some((entry) => entry.id === account.id));
    if (replacement) {
      if (!isActive(replacement.id)) await activate(replacement.id);
    } else if (declared.length > 0) {
      // Every declared account was created above, so this is an inconsistency. Active is a
      // preference the user can set: never delete the selected row and leave the integration
      // without one.
      fail(65, `no declared replacement is present for active ${connection.id}; refusing to retire it`);
    }
  }
  await remove(connection.id);
  connections = await readIntegrations();
}

// Self-heal only the crash state this program can create: the integration has no active credential
// although a declared account exists. An active foreign or manually selected credential is a user
// preference, so it is never replaced.
if (declared.length > 0 && !activeCredentialForIntegration()) {
  const first = declared.find((account) => connections.some((entry) => entry.id === account.id));
  if (first) await activate(first.id);
}

// Enable the native account switch. Read the current profile value and add this provider instead of
// replacing the user's list; the server owns the atomic write and the reload of the managed plugin.
const settings = await api('GET', '/api/config/settings');
if (settings.status !== 200 || typeof settings.body !== 'object' || settings.body === null) {
  fail(75, `could not read OpenChamber settings (HTTP ${settings.status})`);
}
const current = Array.isArray(settings.body.accountSwitchProviders) ? settings.body.accountSwitchProviders : [];
let settingsResult = 'unchanged';
if (declared.length === 0) {
  // The declaration is empty: the managed accounts are gone and the switch entry from this module
  // must not outlive them. Other providers the user configured stay in place.
  if (current.includes(switchProvider)) {
    const next = current.filter((entry) => entry !== switchProvider);
    const saved = await api('PUT', '/api/config/settings', { accountSwitchProviders: next });
    if (saved.status !== 200) fail(65, `could not retire the account switch (HTTP ${saved.status})`);
    const stored = Array.isArray(saved.body?.accountSwitchProviders) ? saved.body.accountSwitchProviders : [];
    if (stored.includes(switchProvider)) fail(65, 'the retired account switch was not removed');
    settingsResult = 'retired';
  }
} else if (!current.includes(switchProvider)) {
  const next = [...current, switchProvider];
  const saved = await api('PUT', '/api/config/settings', { accountSwitchProviders: next });
  if (saved.status !== 200) fail(65, `could not enable the account switch (HTTP ${saved.status})`);
  const stored = Array.isArray(saved.body?.accountSwitchProviders) ? saved.body.accountSwitchProviders : [];
  if (!stored.includes(switchProvider)) fail(65, 'the account switch was not persisted');
  settingsResult = 'updated';
}

// Verify from the catalog, not from what this run intended: one managed row per declared slot, no
// managed row for anything else, and the switch setting present.
connections = await readIntegrations();
const finalOwned = connections.filter((connection) => connection.id.startsWith(PREFIX)).map((connection) => connection.id);
const missing = declared.filter((account) => !finalOwned.includes(account.id));
const unexpected = finalOwned.filter((id) => !declared.some((account) => account.id === id));
if (missing.length > 0 || unexpected.length > 0) {
  fail(65, `catalog verification failed (missing ${missing.length}, unexpected ${unexpected.length})`);
}

const activeID = activeCredentialForIntegration();

// Auditable state without a secret: slot, id and the salted hash the id derives from (root only).
const state = {
  version: 1,
  integrationID,
  slots: Object.fromEntries(
    declared.map((account) => [account.slot, { id: account.id, sha256: account.hash }]),
  ),
  updatedAt: new Date().toISOString(),
};
try {
  fs.mkdirSync(path.dirname(stateFile), { recursive: true, mode: 0o700 });
  fs.writeFileSync(stateFile, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
  fs.chmodSync(stateFile, 0o600);
} catch (error) {
  fail(65, `could not write ${stateFile} (${error instanceof Error ? error.message : String(error)})`);
}

console.log(
  `openchamber go accounts: ${declared.length} managed account(s) verified, ` +
    `active ${activeID ? (finalOwned.includes(activeID) ? activeID : 'external (preserved)') : 'none'}, ` +
    `settings ${settingsResult}`,
);
for (const outcome of outcomes) console.log(`  ${outcome.slot}: ${outcome.result}`);
