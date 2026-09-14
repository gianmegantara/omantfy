import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// ntfy subscriber for the Omarchy bar.
//
// Left click opens the recent-message panel, right click reconnects, middle
// click toggles desktop notifications. The Service streams the configured
// topic and raises Omarchy notifications for each message.
Panel {
  id: root
  moduleName: "gian.omantfy"
  ipcTarget: "gian.omantfy"
  manageIpc: false

  // Every bar surface runs its own Service so each screen's panel has the
  // recent messages, but only the primary screen raises desktop notifications
  // (otherwise a multi-monitor bar toasts each message once per output).
  readonly property string screenName: {
    var win = root.QsWindow ? root.QsWindow.window : null
    return win && win.screen ? String(win.screen.name) : ""
  }
  readonly property var primaryScreen: (Quickshell.screens && Quickshell.screens.length > 0)
    ? Quickshell.screens[0] : null
  readonly property bool isPrimaryScreen: !primaryScreen || screenName === ""
    || String(primaryScreen.name) === screenName

  Service {
    id: svc
    settings: root.settings
    active: true
    notifyAllowed: root.isPrimaryScreen
  }

  readonly property string statusText: {
    switch (svc.status) {
    case "connected":
      if (svc.topics.length === 0) return "Connected"
      if (svc.topics.length === 1) return "Connected · " + svc.topics[0]
      return "Connected · " + svc.topics.length + " topics"
    case "connecting": return "Connecting…"
    case "error": return svc.lastError !== "" ? svc.lastError : "Disconnected"
    case "unconfigured": return "No topic set"
    default: return "Idle"
    }
  }

  readonly property color statusColor: {
    var fg = root.bar ? root.bar.barForeground : Color.foreground
    switch (svc.status) {
    case "connected": return Color.accent
    case "error": return Color.urgent
    case "connecting": return Qt.darker(fg, 1.4)
    default: return Qt.darker(fg, 1.7)
    }
  }

  // ------------------------------------------------------ settings plumbing
  // Read/merge the widget's inline shell.json entry so the panel's Save button
  // persists through the same path the built-in settings UI uses.
  function currentEntry() {
    var config = root.bar && root.bar.shell ? root.bar.shell.shellConfig : null
    var layout = config && config.bar ? config.bar.layout : null
    var sections = ["left", "center", "right"]
    for (var s = 0; layout && s < sections.length; s++) {
      var entries = layout[sections[s]] || []
      for (var i = 0; i < entries.length; i++) {
        if (entries[i] && String(entries[i].id) === root.moduleName) return entries[i]
      }
    }
    return root.settings || {}
  }

  function persistSettings(values) {
    var live = currentEntry()
    var entry = { id: root.moduleName }
    for (var k in live) if (k !== "id") entry[k] = live[k]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleNotifications() {
    root.persistSettings({ notify: !svc.notifyUserEnabled })
  }

  // Icon colour: yellow while there are messages the user has not looked at,
  // otherwise the normal bar foreground.
  readonly property color unreadColor: String(root.setting("unreadColor", "#f5c542"))

  // Opening the panel counts as reading everything currently shown. A message
  // that arrives while the panel is open is also already being looked at.
  onOpenedChanged: if (opened) svc.markRead()

  Connections {
    target: svc
    function onMessageReceived(message) { if (root.opened) svc.markRead() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: svc.glyph
    active: svc.unread
    useActiveColor: true
    activeColor: root.unreadColor
    tooltipText: "ntfy — " + root.statusText
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) svc.reconnect()
      else if (buttonCode === Qt.MiddleButton) root.toggleNotifications()
      else root.toggle()
    }
  }

  // Small status dot in the corner: only visible when not connected.
  Rectangle {
    visible: svc.status !== "connected"
    width: 5
    height: 5
    radius: width / 2
    color: root.statusColor
    anchors.right: button.right
    anchors.bottom: button.bottom
    anchors.rightMargin: 2
    anchors.bottomMargin: 2
  }

  NtfyPanel {
    id: panel
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    messages: svc.messages
    statusText: root.statusText
    statusColor: root.statusColor
    configured: svc.configured
    multiTopic: svc.topics.length > 1
    serverValue: svc.server
    topicValue: svc.topic
    tokenValue: svc.token
    notifyValue: svc.notifyUserEnabled
    soundValue: svc.soundUserEnabled
    soundFileValue: svc.soundFile
    onSaveRequested: function(values) { root.persistSettings(values) }
    onReconnectRequested: svc.reconnect()
    onClearRequested: svc.clear()
    onPreviewSoundRequested: function(path) { svc.playSound(path) }
    onOpenUrl: function(url) { if (url !== "") Quickshell.execDetached(["xdg-open", url]) }
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { svc.reconnect() }
    function reconnect(): void { svc.reconnect() }
    function clear(): void { svc.clear() }
    function status(): string { return svc.status }
    function info(): string {
      return JSON.stringify({
        status: svc.status,
        configured: svc.configured,
        server: svc.server,
        topic: svc.topic,
        topics: svc.topics,
        hasToken: svc.token !== "",
        notify: svc.notifyUserEnabled,
        sound: svc.soundUserEnabled,
        soundFile: svc.soundFile,
        unread: svc.unread,
        messages: svc.messages.length,
        error: svc.lastError
      })
    }
  }
}
