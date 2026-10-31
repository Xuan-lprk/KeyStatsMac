import type { Snapshot } from './schema.ts'
import { defineClientPlugin } from 'c3502/kit'
import { startCollector } from './collector.ts'
import { OptionsSchema, SnapshotSchema } from './schema.ts'

// Derived from the declared schema, never a second handwritten payload contract.
declare global {
  namespace C3502.Client {
    interface Notification {
      'keystats:input:snapshot': { readonly send: { readonly schema: Snapshot } }
    }
  }
}

const plugin = defineClientPlugin({
  id: 'keystats:input',
  apply: 'client',
  provide: () => ({
    name: 'KeyStats native input',
    description: 'Local cumulative keyboard/mouse aggregates. No text or raw input sequence.',
    options: { schema: OptionsSchema },
    notifications: { 'keystats:input:snapshot': { send: { schema: SnapshotSchema } } },
  }),
  setup: async (context) => {
    if (!context.options.enabled) return
    return startCollector({
      binaryPath: context.options.binaryPath,
      requestPermission: context.options.requestPermission,
      onSnapshot: snapshot => context.sendClientNotification({ method: 'keystats:input:snapshot', params: snapshot }),
      onFailure: reason => context.error({ plugin: 'keystats:input' }, reason),
    })
  },
})

// Current C3502 loaders consume the module namespace, not its default export.
export const { id, apply, provide, setup } = plugin
export default plugin
