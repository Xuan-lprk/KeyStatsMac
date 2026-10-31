import { defineConfig } from 'vite-plus'

export default defineConfig({
  pack: {
    entry: ['src/client.ts'],
    format: ['esm'],
    dts: true,
  },
  test: { include: ['src/*.test.ts'] },
})
