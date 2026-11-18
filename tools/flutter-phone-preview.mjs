import { once } from 'node:events'

const [port, app = '5181', width = '390', height = '844'] = process.argv.slice(2)
if (![port, app, width, height].every((value) => /^\d+$/.test(value ?? ''))) {
  throw new Error('Usage: node flutter-phone-preview.mjs <Chrome debug port> [app port] [width] [height]')
}

const origin = 'http://127.0.0.1:' + app
const response = await fetch('http://127.0.0.1:' + port + '/json/list')
if (!response.ok) throw new Error('Chrome debugging endpoint is unavailable')
const pages = await response.json()
const page = pages.find((target) => target.type === 'page' && target.url.startsWith(origin + '/'))
if (!page) throw new Error('Flutter app tab was not found in the debug Chrome instance')
const endpoint = new URL(page.webSocketDebuggerUrl)
if (endpoint.hostname !== '127.0.0.1' && endpoint.hostname !== 'localhost') {
  throw new Error('The debug endpoint must be local')
}

const chrome = new WebSocket(endpoint)
await once(chrome, 'open')
let sequence = 0
const pending = new Map()
chrome.addEventListener('message', (message) => {
  const result = JSON.parse(message.data)
  const request = pending.get(result.id)
  if (!request) return
  pending.delete(result.id)
  if (result.error) request.reject(new Error(result.error.message))
  else request.resolve(result.result)
})

function call(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++sequence
    pending.set(id, { resolve, reject })
    chrome.send(JSON.stringify({ id, method, params }))
  })
}

await call('Emulation.setDeviceMetricsOverride', {
  width: Number(width), height: Number(height), mobile: true,
  screenWidth: Number(width), screenHeight: Number(height),
  deviceScaleFactor: 1, screenOrientation: { type: 'portraitPrimary', angle: 0 },
})
await call('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 })
const viewport = await call('Runtime.evaluate', {
  expression: '({width: innerWidth, height: innerHeight, touch: navigator.maxTouchPoints})',
  returnByValue: true,
})
console.log(JSON.stringify(viewport.result.value))
await once(chrome, 'close')
