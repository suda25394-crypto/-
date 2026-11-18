import { spawn } from 'node:child_process';
import { appendFileSync, mkdirSync, renameSync, watch, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createInterface } from 'node:readline';

const [app, serial] = process.argv.slice(2);
if (!app || !/^emulator-[0-9]+$/.test(serial)) {
  throw new Error('Expected Flutter project directory and an Android emulator serial.');
}
const runtime = join(app, '.dart_tool', 'android-workbench');
mkdirSync(runtime, { recursive: true });
const logPath = join(runtime, 'debug.log');
const statusPath = join(runtime, 'status.json');
let state = { phase: 'starting', device: serial, pid: process.pid, reloads: 0 };
function status(fields) {
  state = { ...state, ...fields, updated: new Date().toISOString() };
  writeFileSync(statusPath + '.tmp', JSON.stringify(state, null, 2));
  renameSync(statusPath + '.tmp', statusPath);
}
function log(text) {
  // Keep debug capabilities, application content, and unstructured device logs out of the log.
  const line = String(text).replace(/(?:https?|wss?):\/\/[^\s)]+/g, '[local endpoint]');
  appendFileSync(logPath, new Date().toISOString() + ' ' + line + '\n');
}
status({});
log('Starting Flutter Android debug session on ' + serial);
const flutter = spawn(process.env.ComSpec || 'cmd.exe', [
  '/d', '/c', 'flutter.bat', 'run', '--debug', '--machine', '-d', serial,
], { cwd: resolve(app), windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });

let appId;
let reloadPending = false;
let activeId;
let nextId = 0;
let timer;
let loggedError = false;
function startPendingReload() {
  if (!appId || state.phase !== 'ready' || activeId || !reloadPending) return;
  reloadPending = false;
  activeId = ++nextId;
  const call = { id: activeId, method: 'app.restart',
    params: { appId, fullRestart: false, reason: 'Dart source saved' } };
  status({ phase: 'reloading' });
  log('Requesting Hot Reload');
  flutter.stdin.write(JSON.stringify([call]) + '\n');
}

function onMessage(msg) {
  const { event, params = {} } = msg;
  if (event === 'app.start') appId = params.appId;
  if (event === 'app.started') {
    status({ phase: 'ready' });
    log('App ready, watching lib/ for Dart edits');
    startPendingReload();
  }
  if (event === 'app.progress' && params.message) log(params.message);
  if (event === 'daemon.logMessage' && params.level === 'error') log(params.message);
  if (event === 'app.stop') log('Flutter app stopped');
  if (activeId && msg.id === activeId) {
    const failed = Boolean(msg.error || msg.result?.code);
    const result = failed ? 'failed' : 'ok';
    log('Hot Reload ' + result + ' ' + (msg.result?.message || msg.error?.message || ''));
    activeId = undefined;
    status({ phase: 'ready', reloads: state.reloads + (failed ? 0 : 1), lastReload: result });
    startPendingReload();
  }
}

createInterface({ input: flutter.stdout }).on('line', line => {
  let batch;
  try { batch = JSON.parse(line); } catch { /* Flutter also prints plain build output. */ }
  if (Array.isArray(batch)) {
    for (const event of batch) onMessage(event);
  } else if (/^\s*(error|failed|exception|unable|could not|failure:|\* what went wrong|> )/i.test(line)) {
    log(line);
  }
});
createInterface({ input: flutter.stderr }).on('line', line => { if (line.trim()) log(line); });
flutter.stdin.on('error', error => log('Flutter input closed: ' + error.message));
const watcher = watch(join(app, 'lib'), { recursive: true }, (_, file) => {
  if (!file?.endsWith('.dart')) return;
  clearTimeout(timer);
  timer = setTimeout(() => { reloadPending = true; startPendingReload(); }, 450);
});
flutter.on('error', error => {
  loggedError = true;
  log('Flutter launch failed: ' + error.message);
});
flutter.on('close', code => {
  watcher.close();
  clearTimeout(timer);
  status({ phase: 'stopped', exitCode: code });
  log('Debug session ended: ' + code);
  process.exitCode = code ?? (loggedError ? 1 : 0);
});
