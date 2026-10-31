import fsPromises from 'node:fs/promises'
import os from 'node:os'
import pathModule from 'node:path'
import process from 'node:process'
import { afterEach, describe, expect, it } from 'vite-plus/test'
import { MessageReader, startCollector } from './collector.ts'
import { OptionsSchema, SnapshotSchema } from './schema.ts'

const sample = {
  schemaVersion: 1 as const,
  kind: 'snapshot' as const,
  keyPresses: 3,
  leftClicks: 1,
  rightClicks: 2,
  middleClicks: 0,
  otherClicks: 0,
  mouseDistancePoints: 5,
  scrollDistanceUnits: 2,
}
const directories: string[] = []
afterEach(async () => {
  await Promise.all(directories.splice(0).map(path => fsPromises.rm(path, { recursive: true, force: true })))
})
async function fixture(source: string) {
  const dir = await fsPromises.mkdtemp(pathModule.join(os.tmpdir(), 'keystats-c3502-'))
  directories.push(dir)
  const path = pathModule.join(dir, 'collector')
  await fsPromises.writeFile(path, `#!${process.execPath}\n${source}`)
  await fsPromises.chmod(path, 0o755)
  return path
}

describe('native collector boundary', () => {
  it('requires explicit enablement and rejects relative binary paths', () => {
    expect(OptionsSchema.parse({ binaryPath: '/collector' }).enabled).toBe(false)
    expect(() => OptionsSchema.parse({ binaryPath: 'collector' })).toThrow()
  })
  it('rejects extra raw-event fields, invalid counts and nonfinite distances', () => {
    expect(() => SnapshotSchema.parse({ ...sample, keyCode: 4 })).toThrow()
    expect(() => SnapshotSchema.parse({ ...sample, keyPresses: -1 })).toThrow()
    expect(() => SnapshotSchema.parse({ ...sample, mouseDistancePoints: Infinity })).toThrow()
  })
  it('handles chunked lines and rejects oversized frames', () => {
    const reader = new MessageReader()
    const encoded = `${JSON.stringify(sample)}\n`
    expect(reader.feed(encoded.slice(0, 10))).toEqual([])
    expect(reader.feed(encoded.slice(10))).toEqual([sample])
    expect(() => reader.feed('x'.repeat(8193))).toThrow()
  })
  it('delivers validated totals and stops the child on disposal', async () => {
    const binaryPath = await fixture(`
      console.log(JSON.stringify({schemaVersion:1,kind:'status',state:'monitoring'}));
      console.log(${JSON.stringify(JSON.stringify(sample))});
      process.stdin.resume(); process.stdin.on('end',()=>process.exit(0));
    `)
    const seen: unknown[] = []
    const failures: string[] = []
    const resource = await startCollector({ binaryPath, requestPermission: false, onSnapshot: async (value) => {
      seen.push(value)
    }, onFailure: value => failures.push(value) })
    await new Promise(resolve => setTimeout(resolve, 30))
    expect(seen).toEqual([sample])
    await resource[Symbol.asyncDispose]()
    expect(failures).toEqual([])
  })
  it('cleans up on protocol failure after readiness and shares concurrent disposal', async () => {
    const binaryPath = await fixture(`
      console.log(JSON.stringify({schemaVersion:1,kind:'status',state:'monitoring'}));
      process.stdin.resume();
      process.on('SIGTERM',()=>{});
      setTimeout(()=>console.log('invalid json'),25);
      setInterval(()=>{},1000);
    `)
    let reportFailure: () => void = () => {}
    const failure = new Promise<void>((resolve) => {
      reportFailure = resolve
    })
    const resource = await startCollector({ binaryPath, requestPermission: false, onSnapshot: async () => {}, onFailure: reportFailure })
    await failure
    const first = resource[Symbol.asyncDispose]()
    const second = resource[Symbol.asyncDispose]()
    expect(first).toBe(second)
    await first
  })
  it('fails clearly when permission is unavailable', async () => {
    const binaryPath = await fixture(`console.log(JSON.stringify({schemaVersion:1,kind:'status',state:'permissionDenied'}));`)
    await expect(startCollector({ binaryPath, requestPermission: false, onSnapshot: async () => {}, onFailure: () => {} })).rejects.toThrow()
  })
  it('reports missing input-monitoring permission instead of successful zero counts', async () => {
    const binaryPath = await fixture(`console.log(JSON.stringify({schemaVersion:1,kind:'status',state:'inputMonitoringDenied'}));`)
    await expect(startCollector({ binaryPath, requestPermission: false, onSnapshot: async () => {}, onFailure: () => {} })).rejects.toThrow('Input Monitoring')
  })
  it('handles spawn errors without hanging', async () => {
    await expect(startCollector({ binaryPath: '/nonexistent-keystats-collector', requestPermission: false, onSnapshot: async () => {}, onFailure: () => {} })).rejects.toThrow()
  })
  it('rejects raw payloads before notifying consumers', async () => {
    const binaryPath = await fixture(`console.log(JSON.stringify({schemaVersion:1,kind:'snapshot',keyCode:4})); process.stdin.resume();`)
    const seen: unknown[] = []
    await expect(startCollector({ binaryPath, requestPermission: false, onSnapshot: async (value) => {
      seen.push(value)
    }, onFailure: () => {} })).rejects.toThrow()
    expect(seen).toEqual([])
  })
})
