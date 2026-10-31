import fs from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'
import url from 'node:url'
import { createC3502Client } from 'c3502/client'

async function main() {
  const here = path.dirname(url.fileURLToPath(import.meta.url))
  const root = path.resolve(here, '../../..')
  const cwd = path.join(root, 'build/C3502/probe')
  await fs.mkdir(cwd, { recursive: true })
  // No network transport plugins. Keep all notifications in this client instance.
  await fs.writeFile(path.join(cwd, 'c3502.json'), JSON.stringify({ plugins: [] }))
  const system = await createC3502Client({ cwd, disableExitListener: true })
  let observer
  let producer
  try {
    observer = await system.pluginManager.addPluginAsync(path.join(here, 'observer.mjs'), {})
    producer = await system.pluginManager.addPluginAsync(path.resolve(here, '../dist/client.mjs'), {
      enabled: true,
      binaryPath: process.env.KEYSTATS_COLLECTOR_BINARY || path.join(root, 'build/C3502/KeyStatsC3502Collector'),
      requestPermission: process.argv.includes('--request-permission'),
    })
    process.stdout.write('Probe running for 30 seconds. Press keys, click or move the mouse; totals update every 5 seconds.\n')
    await new Promise((resolve) => {
      const timer = setTimeout(resolve, 30_000)
      const stop = () => {
        clearTimeout(timer)
        resolve()
      }
      process.once('SIGINT', stop)
      process.once('SIGTERM', stop)
    })
  }
  finally {
    // Explicitly await plugin cleanup: current C3502 system disposal does not await it.
    await producer?.[Symbol.asyncDispose]()
    await observer?.[Symbol.asyncDispose]()
    await system[Symbol.asyncDispose]()
  }
}

main().catch((error) => {
  console.error(error.message)
  process.exitCode = 1
})
