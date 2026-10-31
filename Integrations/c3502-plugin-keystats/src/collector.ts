import type buffer from 'node:buffer'
import type { Snapshot } from './schema.ts'
import child_process from 'node:child_process'
import process from 'node:process'
import { MessageSchema } from './schema.ts'

/** Bounded NDJSON ingress; never include sensitive input in errors. */
export class MessageReader {
  private buffered = ''
  feed(chunk: string): Array<ReturnType<typeof MessageSchema.parse>> {
    this.buffered += chunk
    if (this.buffered.length > 8192) throw new Error('Collector message exceeds size limit')
    const lines = this.buffered.split('\n')
    this.buffered = lines.pop() ?? ''
    return lines.filter(line => line.length > 0).map(line => MessageSchema.parse(JSON.parse(line)))
  }
}

export async function startCollector(options: {
  readonly binaryPath: string
  readonly requestPermission: boolean
  onSnapshot(snapshot: Snapshot): Promise<void>
  onFailure(reason: string): void
}): Promise<AsyncDisposable> {
  if (process.platform !== 'darwin') throw new Error('KeyStats input collector requires macOS')
  const child = child_process.spawn(options.binaryPath, options.requestPermission ? ['--request-permission'] : [], {
    stdio: ['pipe', 'pipe', 'ignore'],
    shell: false,
  })
  const reader = new MessageReader()
  let disposed = false
  let failed = false
  let latest: Snapshot | undefined
  let draining = false
  let ready = false
  let accept: () => void = () => {}
  let reject: (error: Error) => void = () => {}
  const started = new Promise<void>((resolve, fail) => {
    accept = resolve
    reject = fail
  })
  const exited = new Promise<void>(resolve => child.once('close', () => resolve()))

  let startupTimeout: ReturnType<typeof setTimeout> | undefined
  let disposal: Promise<void> | undefined
  const cleanup = async () => {
    disposed = true
    latest = undefined
    clearTimeout(startupTimeout)
    child.stdin.end()
    child.kill('SIGTERM')
    const force = setTimeout(() => child.kill('SIGKILL'), 2000)
    try {
      await exited
    }
    finally { clearTimeout(force) }
  }
  const dispose = () => {
    disposal ??= cleanup()
    return disposal
  }

  const fail = (reason: string) => {
    if (disposed || failed) return
    failed = true
    latest = undefined
    reject(new Error(reason))
    options.onFailure(reason)
    void dispose()
  }
  const drain = async () => {
    if (draining || disposed) return
    draining = true
    try {
      while (latest) {
        if (disposed || failed) break
        const snapshot = latest
        latest = undefined
        await options.onSnapshot(snapshot)
      }
    }
    catch {
      fail('KeyStats notification delivery failed')
    }
    finally { draining = false }
  }
  child.on('error', () => fail('KeyStats collector could not start'))
  child.stdin.on('error', () => {}) // Child may close its pipe before disposal.
  child.on('close', () => {
    if (!disposed) fail('KeyStats collector exited; check its accessibility permission')
  })
  child.stdout.on('data', (chunk: buffer.Buffer) => {
    if (disposed || failed) return
    try {
      for (const message of reader.feed(chunk.toString('utf8'))) {
        if (message.kind === 'status') {
          if (message.state === 'inputMonitoringDenied') {
            fail('KeyStats requires Input Monitoring permission; device control/accessibility alone is insufficient')
            break
          }
          if (message.state === 'permissionDenied') {
            fail('KeyStats accessibility permission is not granted to this launch context')
            break
          }
          if (message.state === 'tapFailed') {
            fail('KeyStats event tap could not be created')
            break
          }
          ready = true
          accept()
        }
        else {
          if (!ready) throw new Error('KeyStats collector sent data before readiness')
          latest = message // At most one pending aggregate, not an event queue.
          void drain()
        }
      }
    }
    catch { fail('Invalid collector stream or accessibility permission unavailable') }
  })
  startupTimeout = setTimeout(fail, 5000, 'KeyStats collector startup timed out')
  try {
    await started
  }
  catch (error) {
    await dispose()
    throw error
  }
  clearTimeout(startupTimeout)
  return { [Symbol.asyncDispose]: dispose }
}
