import { spawn } from 'node:child_process'
import { watch } from 'node:fs'
import { createInterface } from 'node:readline'
import { resolve } from 'node:path'

const [project, port] = process.argv.slice(2)
const flutter = spawn(process.env.ComSpec ?? 'cmd.exe', [
  '/d', '/c', 'flutter.bat', 'run', '-d', 'chrome', '--machine', '--print-dtd',
  '--web-hostname', '127.0.0.1', '--web-port', port,
], { cwd: project, windowsHide: true, stdio: ['pipe', 'pipe', 'inherit'] })
let appId
let ready = false
let seq = 0
let reloadId
let queued = false
let debounce
const input = process.stdin

function request(method, params) {
  const id = ++seq
  flutter.stdin.write(JSON.stringify([{ id, method, params }]) + '\n')
  return id
}

function reload(fullRestart = false) {
  if (!ready || reloadId) {
    queued = true
    return
  }
  reloadId = request('app.restart', { appId, fullRestart, reason: 'couple preview' })
}

function handle(message) {
  const { event, params = {} } = message
  if (event === 'app.start') appId = params.appId
  if (event === 'app.started') {
    ready = true
    console.log('Flutter Chrome 已就绪 · http://127.0.0.1:' + port + '/')
    console.log('保存 Dart 代码会自动热重载 · r 手动重载 · R 重启应用 · q 结束')
    if (queued) { queued = false; reload() }
  }
  if (event === 'app.log' || event === 'daemon.logMessage') console.log(params.log ?? params.message)
  if (event === 'app.progress' && params.message) console.log(params.message)
  if (message.id === reloadId && reloadId) {
    if (message.error || message.result?.code) console.error(message.error ?? message.result?.message)
    else console.log('Hot Reload 完成', message.result?.message ?? '')
    reloadId = undefined
    if (queued) { queued = false; reload() }
  }
}

createInterface({ input: flutter.stdout }).on('line', (line) => {
  try {
    for (const message of JSON.parse(line)) handle(message)
  } catch {
    if (line.trim()) console.log(line)
  }
})
const watcher = watch(resolve(project, 'lib'), { recursive: true }, (_, name) => {
  if (!name?.endsWith('.dart')) return
  clearTimeout(debounce)
  debounce = setTimeout(() => reload(), 550)
})

if (input.isTTY) input.setRawMode(true)
input.resume()
input.on('data', (key) => {
  const value = key.toString().trim()
  if (value === 'r' || value === 'R') reload(value === 'R')
  if (value === 'q' || key.toString() === '\x03') {
    if (appId) request('app.stop', { appId })
    else flutter.kill()
  }
})
flutter.on('exit', (code) => {
  watcher.close()
  clearTimeout(debounce)
  if (input.isTTY) input.setRawMode(false)
  input.pause()
  process.exit(code ?? 1)
})
