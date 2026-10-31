import { z } from 'zod'

const count = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER)
const distance = z.number().finite().nonnegative()
export const SnapshotSchema = z.strictObject({
  schemaVersion: z.literal(1),
  kind: z.literal('snapshot'),
  keyPresses: count,
  leftClicks: count,
  rightClicks: count,
  middleClicks: count,
  otherClicks: count,
  mouseDistancePoints: distance,
  scrollDistanceUnits: distance,
})
export type Snapshot = z.infer<typeof SnapshotSchema>
export const StatusSchema = z.strictObject({
  schemaVersion: z.literal(1),
  kind: z.literal('status'),
  state: z.enum(['monitoring', 'permissionDenied', 'inputMonitoringDenied', 'tapFailed']),
})
export const MessageSchema = z.discriminatedUnion('kind', [SnapshotSchema, StatusSchema])
export const OptionsSchema = z.strictObject({
  enabled: z.boolean().default(false),
  binaryPath: z.string().startsWith('/'),
  requestPermission: z.boolean().default(false),
})
