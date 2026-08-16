function parseEvent(raw) {
  try {
    var event = JSON.parse(String(raw || "").trim())
    if (!event || typeof event !== "object" || !event.type) return null
    return event
  } catch (e) {
    return null
  }
}

function stripAnsi(value) {
  return String(value || "").replace(/\x1b\[[0-9;]*m/g, "").replace(/^\s+|\s+$/g, "")
}

function shortId(value) {
  var text = String(value || "")
  return text.length > 18 ? text.substring(0, 8) + "…" + text.substring(text.length - 6) : text
}

function eventTitle(event) {
  var type = String(event && event.type || "")
  if (type === "message.received") return "Message received"
  if (type === "message.created") return "Message sent"
  if (type === "message.updated") return "Message updated"
  if (type === "typing.changed") return event.data && event.data.is_typing ? "Contact is typing" : "Typing stopped"
  if (type === "contact.created") return "Contact created"
  if (type === "line.assigned") return "Line assigned"
  if (type === "line.unassigned") return "Line unassigned"
  if (type === "line.blocked") return "Line blocked"
  if (type === "line.status.changed") return "Line status changed"
  if (type.indexOf("verification.") === 0) return "Verification " + type.split(".")[1]
  return type
}

function eventDetail(event) {
  var data = event && event.data || {}
  if (event.type.indexOf("message.") === 0)
    return String(data.number || data.sendblue_number || data.status || shortId(data.message_id) || "Message")
  if (event.type === "typing.changed") return String(data.number || "")
  if (event.type.indexOf("line.") === 0)
    return [data.sendblue_number || data.worker_id || "Line", data.status || ""].filter(Boolean).join(" · ")
  if (event.type === "contact.created") return String(data.phone || data.contact_id || "Contact")
  if (event.type.indexOf("verification.") === 0) return shortId(data.verification_sid || "Verification")
  return ""
}

function activityForEvent(event) {
  return {
    id: String(event.id || event.type + ":" + Date.now()),
    type: String(event.type || ""),
    title: eventTitle(event),
    detail: eventDetail(event),
    occurredAt: String(event.occurred_at || new Date().toISOString()),
    recovered: event.recovered === true
  }
}

function prependActivity(activity, event, limit) {
  var row = activityForEvent(event)
  var rows = [row]
  var existing = Array.isArray(activity) ? activity : []
  for (var i = 0; i < existing.length && rows.length < limit; i++) {
    if (existing[i] && existing[i].id !== row.id) rows.push(existing[i])
  }
  return rows
}

function upsertLine(lines, event) {
  var next = {}
  var source = lines && typeof lines === "object" ? lines : {}
  for (var oldKey in source) next[oldKey] = source[oldKey]

  var data = event && event.data || {}
  var workerId = String(data.worker_id || "")
  var number = String(data.sendblue_number || "")
  var existingKey = ""
  for (var candidateKey in next) {
    var candidate = next[candidateKey] || {}
    if ((workerId && candidate.workerId === workerId) || (number && candidate.number === number)) {
      existingKey = candidateKey
      break
    }
  }

  var key = workerId || existingKey || number
  if (!key) return next
  if (existingKey && existingKey !== key) delete next[existingKey]
  if (event.type === "line.unassigned" && !data.effective_until) {
    delete next[key]
    return next
  }

  var current = next[key] || {}
  next[key] = {
    key: key,
    workerId: String(workerId || current.workerId || ""),
    number: String(number || current.number || ""),
    status: String(data.status || (event.type === "line.blocked" ? "BLOCKED" : current.status || "UNKNOWN")),
    assignment: String(data.assignment || (event.type === "line.unassigned" ? "grace_period" : current.assignment || "assigned")),
    effectiveUntil: String(data.effective_until || current.effectiveUntil || ""),
    changedAt: String(data.status_changed_at || data.changed_at || data.blocked_at || data.assigned_at || data.unassigned_at || event.occurred_at || "")
  }
  return next
}

function replaceLines(snapshot) {
  var next = {}
  var data = snapshot && typeof snapshot === "object" ? snapshot : {}
  var rows = Array.isArray(data.lines) ? data.lines : []
  var snapshotAt = String(data.snapshot_at || new Date().toISOString())

  for (var i = 0; i < rows.length; i++) {
    var line = rows[i]
    if (!line || typeof line !== "object") continue
    next = upsertLine(next, {
      type: "line.status.changed",
      occurred_at: String(line.status_changed_at || snapshotAt),
      data: line
    })
  }
  return next
}

function lineRows(lines) {
  var rows = []
  var source = lines && typeof lines === "object" ? lines : {}
  for (var key in source) rows.push(source[key])
  rows.sort(function(a, b) { return String(a.number || a.workerId).localeCompare(String(b.number || b.workerId)) })
  return rows
}

function hasLineProblem(lines) {
  var rows = lineRows(lines)
  for (var i = 0; i < rows.length; i++) {
    if (["OFFLINE", "DEGRADED", "BLOCKED"].indexOf(rows[i].status) !== -1) return true
  }
  return false
}

if (typeof module !== "undefined") {
  module.exports = {
    parseEvent: parseEvent,
    stripAnsi: stripAnsi,
    shortId: shortId,
    eventTitle: eventTitle,
    eventDetail: eventDetail,
    activityForEvent: activityForEvent,
    prependActivity: prependActivity,
    upsertLine: upsertLine,
    replaceLines: replaceLines,
    lineRows: lineRows,
    hasLineProblem: hasLineProblem
  }
}
