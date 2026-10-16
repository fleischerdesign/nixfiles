const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const { pathToFileURL } = require('node:url');

(async () => {
  const runtime = process.argv[2];
  const app = path.join(runtime, 'resources/app');
  const requireApp = createRequire(path.join(app, 'package.json'));
  for (const file of ['dist-bundle/entry.mjs', 'dist-bundle/main.mjs', 'dist-bundle/early-startup.mjs', 'preload.mjs']) {
    assert.ok(fs.statSync(path.join(app, file)).size > 0, file);
  }
  assert.ok(fs.readFileSync(path.join(runtime, 'resources/web-dist/index.html'), 'utf8').includes('<html'));
  assert.ok(requireApp('sherpa-onnx-node'));
  const pty = requireApp('node-pty');
  const expected = 'openchamber-native-pty-ok';
  await new Promise((resolve, reject) => {
    const terminal = pty.spawn(process.argv[3], ['-c', `printf '${expected}'; pwd`], {
      cwd: process.env.TMPDIR,
      env: process.env,
      name: 'xterm-256color',
      cols: 80,
      rows: 24,
    });
    let output = '';
    const timeout = setTimeout(() => { terminal.kill(); reject(new Error('PTY timed out')); }, 10000);
    terminal.onData(data => { output += data; });
    terminal.onExit(({ exitCode }) => {
      clearTimeout(timeout);
      try {
        assert.equal(exitCode, 0);
        assert.ok(output.includes(expected), output);
        assert.ok(output.includes(process.env.TMPDIR), output);
        resolve();
      } catch (error) { reject(error); }
    });
  });
  const server = await import(pathToFileURL(requireApp.resolve('@openchamber/web/server/index.js')));
  assert.equal(typeof server.startWebUiServer, 'function');
  console.log('ok: packaged UI, server import, native speech addon and PTY execution');
  process.exit(0);
})().catch(error => { console.error(error); process.exit(1); });
