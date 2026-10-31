import process from 'node:process'
import { defineClientPlugin } from 'c3502/kit'
import { z } from 'zod'

const plugin = defineClientPlugin({
  id: 'keystats:probe',
  apply: 'client',
  provide: () => ({
    name: 'KeyStats probe',
    description: 'Prints aggregate counts received through C3502 local notifications.',
    options: { schema: z.strictObject({}).default({}) },
  }),
  setup: context => context.onClientNotification('keystats:input:snapshot', (event) => {
    // Aggregate counts only. No raw event, key identity or timestamp is available.
    process.stdout.write(`C3502 received: ${JSON.stringify(event.params)}\n`)
  }),
})

// Current C3502 loaders consume the module namespace, not its default export.
export const { id, apply, provide, setup } = plugin
export default plugin
