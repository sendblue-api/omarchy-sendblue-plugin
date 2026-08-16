const assert = require('node:assert/strict')
const test = require('node:test')
const Model = require('../Model.js')

test('parses JSONL and ignores invalid output', () => {
  assert.equal(Model.parseEvent('not json'), null)
  assert.equal(Model.parseEvent('{"type":"message.received"}').type, 'message.received')
})

test('reconciles number-only assignment with a later worker snapshot', () => {
  let lines = Model.upsertLine({}, {
    type: 'line.assigned',
    occurred_at: '2026-08-16T00:00:00.000Z',
    data: { sendblue_number: '+15550000001' }
  })
  lines = Model.upsertLine(lines, {
    type: 'line.status.changed',
    occurred_at: '2026-08-16T00:01:00.000Z',
    data: { worker_id: 'worker-1', sendblue_number: '+15550000001', status: 'ONLINE' }
  })

  assert.deepEqual(Object.keys(lines), ['worker-1'])
  assert.equal(lines['worker-1'].status, 'ONLINE')
})

test('removes an immediately unassigned line and retains a grace-period line', () => {
  const initial = Model.upsertLine({}, {
    type: 'line.status.changed',
    occurred_at: '2026-08-16T00:00:00.000Z',
    data: { worker_id: 'worker-1', sendblue_number: '+15550000001', status: 'ONLINE' }
  })
  const removed = Model.upsertLine(initial, {
    type: 'line.unassigned',
    occurred_at: '2026-08-16T00:01:00.000Z',
    data: { worker_id: 'worker-1', sendblue_number: '+15550000001', effective_until: null }
  })
  assert.deepEqual(removed, {})

  const retained = Model.upsertLine(initial, {
    type: 'line.unassigned',
    occurred_at: '2026-08-16T00:01:00.000Z',
    data: {
      worker_id: 'worker-1',
      sendblue_number: '+15550000001',
      effective_until: '2026-08-17T00:00:00.000Z'
    }
  })
  assert.equal(retained['worker-1'].assignment, 'grace_period')
})

test('authoritative snapshots replace stale lines and refresh unchanged health rows', () => {
  const existing = {
    stale: {
      key: 'stale',
      workerId: 'stale',
      number: '+15550000000',
      status: 'ONLINE',
      assignment: 'assigned',
      effectiveUntil: '',
      changedAt: '2026-08-16T00:00:00.000Z'
    }
  }

  let replaced = existing
  replaced = Model.replaceLines({
    snapshot_at: '2026-08-16T01:00:00.000Z',
    lines: [{
      worker_id: 'worker-1',
      sendblue_number: '+15550000001',
      status: 'ONLINE',
      status_changed_at: '2026-08-16T00:00:00.000Z',
      assignment: 'grace_period',
      effective_until: '2026-08-17T00:00:00.000Z'
    }]
  })

  assert.deepEqual(Object.keys(replaced), ['worker-1'])
  assert.equal(replaced['worker-1'].assignment, 'grace_period')
  assert.equal(replaced['worker-1'].number, '+15550000001')
})

test('an empty authoritative snapshot clears all lines', () => {
  assert.deepEqual(Model.replaceLines({ lines: [], snapshot_at: '2026-08-16T01:00:00.000Z' }), {})
})
