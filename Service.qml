import QtQuick
import Quickshell
import Quickshell.Io

// Headless ntfy subscriber. Streams a topic over HTTP (curl --fail --no-buffer)
// and turns each message event into a desktop notification, while keeping a
// bounded recent message list for the bar widget's panel.
//
// Instantiated by BarWidget (one per screen). `notifyAllowed` lets the widget
// mute notifications on secondary screens so a multi-monitor bar does not raise
// the same toast once per output; every instance still streams so each screen's
// panel has its own copy of the recent messages.
Item {
  id: service

  property var settings: ({})
  property bool active: false
  property bool notifyAllowed: true

  readonly property string defaultServer: "https://ntfy.giandev.site"

  readonly property string server: normalizeServer(String(setting("server", defaultServer)))
  readonly property string topic: String(setting("topic", "")).trim()
  readonly property var topics: parseTopics(topic)
  readonly property string topicPath: topics.join(",")
  readonly property string token: String(setting("token", "")).trim()
  readonly property string glyph: String(setting("glyph", "󰂚"))
  readonly property int maxMessages: Math.max(1, Math.min(200, intSetting("maxMessages", 30)))
  readonly property bool notifyUserEnabled: boolSetting("notify", true)
  readonly property bool notifyEnabled: notifyAllowed && notifyUserEnabled
  readonly property bool soundUserEnabled: boolSetting("sound", true)
  readonly property bool soundEnabled: notifyAllowed && soundUserEnabled
  readonly property string soundFile: String(setting("soundFile", "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga")).trim()

  readonly property bool configured: topics.length > 0
  readonly property bool shouldStream: active && configured

  // idle | connecting | connected | error | unconfigured
  property string status: "idle"
  property string lastError: ""
  property var messages: []
  property double lastMessageAt: 0
  // True while messages have arrived since the panel was last opened. Drives
  // the bar icon's unread colour.
  property bool unread: false

  signal messageReceived(var message)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (typeof value === "boolean") return value
    var text = String(value).trim().toLowerCase()
    if (text === "true" || text === "1" || text === "yes" || text === "on") return true
    if (text === "false" || text === "0" || text === "no" || text === "off") return false
    return fallback
  }

  function intSetting(name, fallback) {
    var n = parseInt(String(setting(name, fallback)), 10)
    return isFinite(n) ? n : fallback
  }

  function normalizeServer(raw) {
    var text = String(raw || "").trim()
    if (text === "") return defaultServer
    if (!/^https?:\/\//i.test(text)) text = "https://" + text
    return text.replace(/\/+$/, "")
  }

  // Topics may be comma- or whitespace-separated; ntfy accepts a
  // comma-separated list in a single subscription, so one stream covers them
  // all. Order is preserved and duplicates are dropped.
  function parseTopics(raw) {
    var text = String(raw || "").trim()
    if (text === "") return []
    var parts = text.split(/[,\s]+/)
    var out = []
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i].trim()
      if (part !== "" && out.indexOf(part) === -1) out.push(part)
    }
    return out
  }

  readonly property var streamCommand: {
    var cmd = ["curl", "-s", "-S", "--fail", "--no-buffer", "--connect-timeout", "10"]
    if (token !== "") cmd.push("-H", "Authorization: Bearer " + token)
    cmd.push(server + "/" + topicPath + "/json")
    return cmd
  }

  // ------------------------------------------------------------ streaming
  // `streaming` (not the Process's `running`) is the source of truth so the
  // reconnect and command-change paths can stop and restart deliberately.
  property bool streaming: false

  // Coalesces the several bindings that can fire for one settings change
  // (shouldStream, configured, command) into a single deferred restart. The
  // deferral also makes the false->true transition observable to the Process's
  // `running` binding, and stops a just-started stream from being torn down
  // again before it has a chance to report `open`.
  property bool restartQueued: false

  // Number of in-flight intentional stops. A stopped process still reports an
  // exit asynchronously, which can arrive after the replacement has started;
  // counting them lets onExited tell an intentional restart from a real drop.
  property int pendingStops: 0

  function scheduleStream() {
    if (!shouldStream) {
      if (streaming) {
        pendingStops++
        streaming = false
      }
      status = configured ? "idle" : "unconfigured"
      return
    }
    if (streaming) {
      pendingStops++
      streaming = false
    }
    status = "connecting"
    if (restartQueued) return
    restartQueued = true
    Qt.callLater(function() {
      service.restartQueued = false
      if (service.shouldStream) service.streaming = true
    })
  }

  onShouldStreamChanged: scheduleStream()
  onConfiguredChanged: scheduleStream()
  Component.onCompleted: scheduleStream()

  function reconnect() {
    lastError = ""
    scheduleStream()
  }

  Process {
    id: streamProc
    running: service.streaming
    command: service.streamCommand

    stdout: SplitParser {
      onRead: function(line) { service.handleLine(line) }
    }

    stderr: StdioCollector {
      id: errCollector
      waitForEnd: true
      onStreamFinished: {
        var text = String(errCollector.text || "").trim()
        if (text !== "") service.lastError = text.split("\n").pop()
      }
    }

    // A settings change (server/topic/token) rewrites `command`, so route it
    // through the same coalesced restart. This also reconnects a stream parked
    // on an auth error once the user corrects the token or topic.
    onCommandChanged: service.scheduleStream()

    onExited: function(code) {
      // An exit we asked for (restart / teardown) is not a failure.
      if (service.pendingStops > 0) {
        service.pendingStops--
        return
      }
      if (!service.streaming) return
      service.streaming = false
      service.status = "error"
      // Exit and stream-finished have no guaranteed order, so fall back to the
      // collector's buffer when the stderr handler has not run yet.
      var err = String(service.lastError || "").trim()
      if (err === "") {
        var collected = String(errCollector.text || "").trim()
        err = collected !== "" ? collected.split("\n").pop() : "disconnected (curl exit " + code + ")"
        service.lastError = err
      }
      // 401/403 means the topic or token is wrong. Retrying on a timer would
      // hammer the server forever; wait for a settings change or a manual
      // reconnect instead.
      if (service.isAuthError()) return
      restartTimer.restart()
    }
  }

  function isAuthError() {
    return /\b(401|403)\b/.test(String(lastError || ""))
  }

  Timer {
    id: restartTimer
    interval: 5000
    repeat: false
    onTriggered: {
      if (service.shouldStream) {
        service.status = "connecting"
        service.streaming = true
      }
    }
  }

  // ------------------------------------------------------------- messages

  function handleLine(line) {
    var text = String(line || "").trim()
    if (text === "") return

    var obj
    try {
      obj = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!obj || typeof obj !== "object") return

    var event = String(obj.event || "")
    if (event === "open") {
      status = "connected"
      lastError = ""
      return
    }
    // Only real message events become notifications. Anything else (keepalive,
    // poll_request, or an error body that slipped past curl's --fail) is
    // ignored rather than mistaken for a message.
    if (event !== "message") return

    var msg = normalizeMessage(obj)
    if (!msg) return

    messages = [msg].concat(messages).slice(0, maxMessages)
    lastMessageAt = Date.now()
    unread = true
    messageReceived(msg)
    if (notifyEnabled) sendNotification(msg)
    if (soundEnabled) playSound()
  }

  function normalizeMessage(obj) {
    var id = String(obj.id || "")
    if (id === "") id = "local-" + Date.now() + "-" + Math.random().toString(36).slice(2, 7)
    return {
      id: id,
      time: obj.time ? Number(obj.time) * 1000 : Date.now(),
      topic: String(obj.topic || (topics.length > 0 ? topics[0] : "")),
      title: String(obj.title || ""),
      body: String(obj.message || ""),
      priority: Number(obj.priority || 3),
      tags: Array.isArray(obj.tags) ? obj.tags.map(String) : [],
      click: String(obj.click || ""),
      icon: String(obj.icon || "")
    }
  }

  function urgencyFor(priority) {
    if (priority <= 2) return "low"
    if (priority >= 5) return "critical"
    return "normal"
  }

  function sendNotification(msg) {
    var title = msg.title !== "" ? msg.title : (msg.topic !== "" ? msg.topic : "ntfy")
    var args = ["omarchy-notification-send", "--app-name", "ntfy", "-g", glyph, "-u", urgencyFor(msg.priority)]
    if (msg.icon !== "") args.push("-i", msg.icon)
    if (msg.priority >= 5) args.push("-t", "0")
    args.push(title)
    if (msg.body !== "") args.push(msg.body)
    if (msg.click !== "") args.push("--exec", "xdg-open", msg.click)
    Quickshell.execDetached(args)
  }

  function clear() {
    messages = []
    unread = false
  }

  function markRead() {
    unread = false
  }

  // Play the notification sound with PipeWire. `path` lets the settings panel
  // preview an unsaved file; the automatic path uses the configured soundFile.
  function playSound(path) {
    var file = (path === undefined || path === null || path === "") ? soundFile : String(path)
    if (file === "") return
    Quickshell.execDetached(["pw-play", file])
  }
}
