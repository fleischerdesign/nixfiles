// Fixture for the Go account seed: a fake OpenChamber API plus a real node:sqlite credential table,
// so the reconcile decisions are observed at the consumer boundary. No production access, no keys.
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';

const seed = process.argv[2];
if (!seed) throw new Error('usage: openchamber-go-accounts.test.mjs <go-accounts.mjs>');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'goacc-fixture-'));
fs.mkdirSync(`${root}/creds`, { recursive: true });
const dbPath = `${root}/opencode.db`;

const db = new DatabaseSync(dbPath);
db.exec('create table credential (id text primary key, integration_id text, label text, active integer not null default 0)');
const rows = () => db.prepare('select * from credential').all();
const find = (id) => db.prepare('select * from credential where id = ?').get(id);
const activeFor = (integration) => db.prepare('select id from credential where integration_id = ? and active = 1').get(integration)?.id ?? null;
const setActive = (id) => {
  const row = find(id);
  db.prepare('update credential set active = 0 where integration_id = ?').run(row.integration_id);
  db.prepare('update credential set active = 1 where id = ?').run(id);
};

fs.writeFileSync(`${root}/creds/ui_password`, 'pw\n');
for (const slot of ['go-1', 'go-2', 'go-3']) fs.writeFileSync(`${root}/creds/${slot}`, `${slot}-key\n`);

const state = { settings: { theme: 'dark', accountSwitchProviders: [] }, calls: [], failActivate: false };
const server = http.createServer(async (req, res) => {
  let body = '';
  for await (const chunk of req) body += chunk;
  const url = new URL(req.url, 'http://x');
  const json = (status, value) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(value)); };
  if (url.pathname === '/auth/session' && req.method === 'POST') {
    if (JSON.parse(body).password !== 'pw') return json(401, {});
    res.writeHead(200, { 'set-cookie': 'oc_ui_session=token; Path=/; HttpOnly' });
    return res.end('{}');
  }
  if (!(req.headers.cookie || '').startsWith('oc_ui_session=')) return json(401, {});
  state.calls.push(`${req.method} ${url.pathname}`);
  if (url.pathname === '/api/integration') {
    return json(200, {
      data: [{
        id: 'opencode-go',
        connections: rows()
          .filter((row) => row.integration_id === 'opencode-go')
          .map((row) => ({ type: 'credential', id: row.id, label: row.label, method: 'key' })),
      }],
    });
  }
  if (url.pathname === '/api/credential' && req.method === 'POST') {
    const input = JSON.parse(body);
    if (find(input.id)) return json(409, { error: 'conflict' });
    const integration = input.integrationID;
    const already = activeFor(integration);
    const active = input.activate === false ? (already ? 0 : 1) : 1;
    db.prepare('insert into credential (id, integration_id, label, active) values (?,?,?,0)').run(input.id, integration, input.label);
    if (active) setActive(input.id);
    return json(200, { data: { id: input.id, integrationID: integration, label: input.label, active: Boolean(active) } });
  }
  const act = url.pathname.match(/^\/api\/credential\/([^/]+)\/activate$/);
  if (act && req.method === 'POST') {
    if (state.failActivate) return json(500, { error: 'injected' });
    if (!find(decodeURIComponent(act[1]))) return json(404, {});
    setActive(decodeURIComponent(act[1]));
    res.writeHead(204);
    return res.end();
  }
  const del = url.pathname.match(/^\/api\/credential\/([^/]+)$/);
  if (del && req.method === 'DELETE') {
    const id = decodeURIComponent(del[1]);
    if (!find(id)) return json(404, {});
    db.prepare('delete from credential where id = ?').run(id);
    res.writeHead(204);
    return res.end();
  }
  if (url.pathname === '/api/config/settings' && req.method === 'GET') return json(200, state.settings);
  if (url.pathname === '/api/config/settings' && req.method === 'PUT') {
    state.settings = { ...state.settings, ...JSON.parse(body) };
    return json(200, state.settings);
  }
  return json(404, {});
});

await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const serverUrl = `http://127.0.0.1:${server.address().port}`;

const runSeed = async (slots) => {
  fs.writeFileSync(`${root}/config.json`, JSON.stringify({
    serverUrl,
    integrationID: 'opencode-go',
    switchProvider: 'opencode-go',
    stateFile: `${root}/state.json`,
    opencodeDatabase: dbPath,
    slots: slots.map((slot) => ({ slot, secretId: slot, secret: `sops:${slot}` })),
  }));
  state.calls = [];
  return await new Promise((resolve) => {
    const child = spawn(process.execPath, [seed], {
      env: { ...process.env, OPENCHAMBER_GO_CONFIG: `${root}/config.json`, CREDENTIALS_DIRECTORY: `${root}/creds` },
    });
    let out = '';
    let err = '';
    child.stdout.on('data', (chunk) => (out += chunk));
    child.stderr.on('data', (chunk) => (err += chunk));
    child.on('close', (code) => resolve({ code, out, err, calls: [...state.calls] }));
  });
};

const failures = [];
const check = (name, ok, detail = '') => {
  if (!ok) failures.push(`${name}${detail ? `: ${detail}` : ''}`);
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : ` -- ${detail}`}`);
};
const ownedRows = () => rows().filter((row) => row.id.startsWith('cred_nixfiles_go_'));
const activeOwned = () => ownedRows().filter((row) => row.active);
const idOf = (slot) => rows().find((row) => row.label === `nixfiles: ${slot}`)?.id;
const writes = (calls) => calls.filter((call) => /^(POST|DELETE|PUT)/.test(call));
const selectRow = (id) => {
  const integration = find(id).integration_id;
  db.prepare('update credential set active = 0 where integration_id = ?').run(integration);
  db.prepare('update credential set active = 1 where id = ?').run(id);
};

// A. fresh create selects the first account and enables the switch.
let result = await runSeed(['go-1', 'go-2', 'go-3']);
check('fresh exit 0', result.code === 0, result.err.trim());
check('fresh creates 3', ownedRows().length === 3, JSON.stringify(rows()));
check('fresh selects first', activeOwned().map((row) => row.label).join() === 'nixfiles: go-1');
check('fresh enables switch', state.settings.accountSwitchProviders.join() === 'opencode-go');

// B. idempotence writes nothing at all.
result = await runSeed(['go-1', 'go-2', 'go-3']);
check('rerun exit 0', result.code === 0, result.err.trim());
check('rerun writes nothing', writes(result.calls).length === 0, result.calls.join(' | '));

// A foreign OAuth login on another integration must survive every later step.
db.prepare(
  "insert into credential (id, integration_id, label, active) values ('cred_chatgpt_manual','opencode','ChatGPT',1)",
).run();

// C. rotating the selected slot activates the replacement before deleting the old row.
const firstID = idOf('go-1');
fs.writeFileSync(`${root}/creds/go-1`, 'go-1-rotated\n');
result = await runSeed(['go-1', 'go-2', 'go-3']);
const rotatedID = idOf('go-1');
check('rotate exit 0', result.code === 0, result.err.trim());
check('rotate changes id', Boolean(rotatedID) && rotatedID !== firstID, `${firstID} -> ${rotatedID}`);
check('rotate removes old row', !rows().some((row) => row.id === firstID));
check('rotate keeps selection on new row', rows().find((row) => row.id === rotatedID)?.active === 1);
check(
  'rotate activates before delete',
  result.calls.indexOf(`POST /api/credential/${rotatedID}/activate`) < result.calls.indexOf(`DELETE /api/credential/${firstID}`),
  result.calls.join(' | '),
);

// D. rotating a non-selected slot never activates it.
fs.writeFileSync(`${root}/creds/go-2`, 'go-2-rotated\n');
result = await runSeed(['go-1', 'go-2', 'go-3']);
check('inactive rotate no activate', !result.calls.some((call) => call.includes('/activate')), result.calls.join(' | '));
check('inactive rotate keeps open selection', activeOwned().map((row) => row.label).join() === 'nixfiles: go-1');

// E. retiring a non-selected slot leaves the selection untouched.
const staleInactive = idOf('go-3');
result = await runSeed(['go-1', 'go-2']);
check('retire inactive exit 0', result.code === 0, result.err.trim());
check('retire inactive removes row', !rows().some((row) => row.id === staleInactive));
check('retire inactive keeps selection', activeOwned().map((row) => row.label).join() === 'nixfiles: go-1');
check('retire inactive no activate', !result.calls.some((call) => call.includes('/activate')), result.calls.join(' | '));

// F. retiring the selected slot selects the declared replacement first.
const retiredActive = idOf('go-1');
const replacementID = idOf('go-2');
result = await runSeed(['go-2']);
check('retire active exit 0', result.code === 0, result.err.trim());
check('retire active leaves one selection', activeOwned().length === 1, JSON.stringify(activeOwned()));
check('retire active selects replacement', activeOwned()[0]?.label === 'nixfiles: go-2');
check(
  'retire active activates before delete',
  result.calls.indexOf(`POST /api/credential/${replacementID}/activate`) < result.calls.indexOf(`DELETE /api/credential/${retiredActive}`),
  result.calls.join(' | '),
);

// G. a failed activation aborts before the delete, leaving the old selection intact.
result = await runSeed(['go-1', 'go-2']);
const go1 = idOf('go-1');
const go2 = idOf('go-2');
selectRow(go1);
state.failActivate = true;
result = await runSeed(['go-2']);
state.failActivate = false;
check('failed retire exits non-zero', result.code !== 0, `${result.code} ${result.err.trim()}`);
check('failed retire keeps old row', rows().some((row) => row.id === go1), JSON.stringify(rows()));
check('failed retire keeps old row active', rows().find((row) => row.id === go1)?.active === 1, JSON.stringify(rows()));
check('failed retire deletes nothing', !result.calls.some((call) => call.startsWith('DELETE')), result.calls.join(' | '));

// H. the next healthy run finishes the interrupted retirement.
result = await runSeed(['go-2']);
check('retry after failure exit 0', result.code === 0, result.err.trim());
check('retry removes stale row', !rows().some((row) => row.id === go1));
check('retry selects declared row', rows().find((row) => row.id === go2)?.active === 1, JSON.stringify(rows()));

// I. an integration left without any selection heals from the declaration.
db.exec("update credential set active = 0 where integration_id = 'opencode-go'");
result = await runSeed(['go-2']);
check('heal exit 0', result.code === 0, result.err.trim());
check('heal selects a declared row', activeOwned().map((row) => row.label).join() === 'nixfiles: go-2', JSON.stringify(activeOwned()));
check(
  'heal activates exactly the declared row',
  result.calls.filter((call) => call.includes('/activate')).length === 1,
  result.calls.join(' | '),
);

// J. a foreign selection inside the same integration is a preference, never replaced.
db.prepare(
  "insert into credential (id, integration_id, label, active) values ('cred_foreign_go','opencode-go','Manual Go',1)",
).run();
db.exec("update credential set active = 0 where id like 'cred_nixfiles_go_%'");
result = await runSeed(['go-2']);
check('foreign active exit 0', result.code === 0, result.err.trim());
check('foreign active not replaced', rows().find((row) => row.id === 'cred_foreign_go')?.active === 1, JSON.stringify(activeOwned()));
check('foreign active means no owned activation', !result.calls.some((call) => call.includes('/activate')), result.calls.join(' | '));
check('foreign active leaves owned row inactive', rows().find((row) => row.id === go2)?.active === 0);

// K. an empty declaration cleans up owned rows and the switch, keeping foreign logins and settings.
result = await runSeed([]);
check('cleanup exit 0', result.code === 0, result.err.trim());
check('cleanup removes owned rows', ownedRows().length === 0, JSON.stringify(rows()));
check('cleanup keeps ChatGPT OAuth row', rows().some((row) => row.id === 'cred_chatgpt_manual'));
check('cleanup keeps ChatGPT OAuth active', rows().find((row) => row.id === 'cred_chatgpt_manual')?.active === 1);
check('cleanup keeps foreign Go row', rows().some((row) => row.id === 'cred_foreign_go'));
check('cleanup keeps foreign Go active', rows().find((row) => row.id === 'cred_foreign_go')?.active === 1);
check('cleanup retires switch', state.settings.accountSwitchProviders.length === 0, JSON.stringify(state.settings));
check('cleanup keeps other settings', state.settings.theme === 'dark');

// L. an owned-looking id that does not match the managed shape is refused, not guessed.
db.prepare(
  "insert into credential (id, integration_id, label, active) values ('cred_nixfiles_go_looks-wrong','opencode-go','x',0)",
).run();
result = await runSeed([]);
check('malformed owned id refused', result.code === 65, `${result.code} ${result.err.trim()}`);
check('malformed owned id not removed', rows().some((row) => row.id === 'cred_nixfiles_go_looks-wrong'));

server.close();
console.log(failures.length ? `\n${failures.length} failure(s)` : '\nall checks passed');
process.exit(failures.length ? 1 : 0);
