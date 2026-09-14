import QtQuick
import QtQuick.Layouts
import qs.Ui
import qs.Commons

// Popup for the Omantfy bar widget: connection status, an editable server /
// topic / token form, and the recent messages the Service has received.
KeyboardPanel {
  id: panel

  property var messages: []
  property string statusText: ""
  property color statusColor: Color.foreground
  property bool configured: false
  property bool multiTopic: false
  property string serverValue: ""
  property string topicValue: ""
  property string tokenValue: ""
  property bool notifyValue: true
  property bool soundValue: true
  property string soundFileValue: ""

  property bool settingsOpen: false

  signal saveRequested(var values)
  signal reconnectRequested()
  signal clearRequested()
  signal previewSoundRequested(string path)
  signal openUrl(string url)

  contentWidth: panel.fittedContentWidth(Style.space(360))
  contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(620))
  focusTarget: keyCatcher

  readonly property real rowFillAlpha: 0.05

  function formatTime(ms) {
    if (!ms) return ""
    return Qt.formatTime(new Date(ms), "HH:mm")
  }

  function tagText(msg) {
    if (!msg || !msg.tags || msg.tags.length === 0) return ""
    return msg.tags.join("  ")
  }

  function syncFields() {
    serverField.text = panel.serverValue
    topicField.text = panel.topicValue
    tokenField.text = panel.tokenValue
    notifySwitch.checked = panel.notifyValue
    soundSwitch.checked = panel.soundValue
    soundFileField.text = panel.soundFileValue
  }

  function submitSettings() {
    panel.saveRequested({
      server: String(serverField.text || "").trim(),
      topic: String(topicField.text || "").trim(),
      token: String(tokenField.text || "").trim(),
      notify: !!notifySwitch.checked,
      sound: !!soundSwitch.checked,
      soundFile: String(soundFileField.text || "").trim()
    })
  }

  onOpenChanged: {
    if (open) {
      panel.settingsOpen = !panel.configured
      panel.syncFields()
    }
  }

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    blocked: topicField.activeFocus || serverField.activeFocus || tokenField.activeFocus
    onCloseRequested: panel.close()

    ColumnLayout {
      id: body
      width: parent.width
      spacing: Style.space(10)

      // ------------------------------------------------------------- header
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Rectangle {
          Layout.preferredWidth: 8
          Layout.preferredHeight: 8
          Layout.alignment: Qt.AlignVCenter
          radius: 4
          color: panel.statusColor
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          Text {
            text: "ntfy"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            text: panel.statusText
            color: Qt.darker(Color.foreground, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }

        Button {
          text: "󰑓"
          tooltipText: "Reconnect"
          bordered: false
          onClicked: panel.reconnectRequested()
        }

        Button {
          text: "󰒓"
          tooltipText: panel.settingsOpen ? "Hide settings" : "Settings"
          bordered: false
          active: panel.settingsOpen
          onClicked: panel.settingsOpen = !panel.settingsOpen
        }
      }

      // ----------------------------------------------------------- settings
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(5)
        visible: panel.settingsOpen || !panel.configured

        Text {
          text: "Server"
          color: Qt.darker(Color.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        TextField {
          id: serverField
          Layout.fillWidth: true
          placeholderText: "https://ntfy.sh"
          onAccepted: panel.submitSettings()
        }

        Text {
          text: "Topics (comma-separated)"
          color: Qt.darker(Color.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        TextField {
          id: topicField
          Layout.fillWidth: true
          placeholderText: "my-topic, another-topic"
          onAccepted: panel.submitSettings()
        }

        Text {
          text: "Access token (optional)"
          color: Qt.darker(Color.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        TextField {
          id: tokenField
          Layout.fillWidth: true
          password: true
          placeholderText: "tk_…"
          onAccepted: panel.submitSettings()
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: "Desktop notifications"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          ToggleSwitch {
            id: notifySwitch
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: "Play a sound"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Button {
            text: "󰓃"
            tooltipText: "Preview sound"
            bordered: false
            onClicked: panel.previewSoundRequested(String(soundFileField.text || "").trim())
          }

          ToggleSwitch {
            id: soundSwitch
          }
        }

        TextField {
          id: soundFileField
          Layout.fillWidth: true
          placeholderText: "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga"
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Button {
            text: "Save"
            onClicked: panel.submitSettings()
          }

          Item { Layout.fillWidth: true }

          Button {
            text: "Clear messages"
            onClicked: panel.clearRequested()
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(2)
          Layout.bottomMargin: Style.space(2)
        }
      }

      // ----------------------------------------------------------- messages
      Flickable {
        id: messageList
        Layout.fillWidth: true
        Layout.preferredHeight: panel.listHeight
        contentWidth: width
        contentHeight: listColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: listColumn
          width: messageList.width
          spacing: Style.space(6)

          Repeater {
            model: panel.messages

            delegate: Rectangle {
              id: row
              required property var modelData
              required property int index

              width: listColumn.width
              implicitHeight: rowColumn.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b,
                             rowArea.containsMouse && row.modelData.click !== "" ? panel.rowFillAlpha * 2 : panel.rowFillAlpha)
              border.width: 1
              border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)

              Column {
                id: rowColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: (row.modelData.priority >= 5 ? "󰀦 " : "") + (row.modelData.title !== "" ? row.modelData.title : row.modelData.topic)
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  wrapMode: Text.Wrap
                }

                Text {
                  width: parent.width
                  visible: row.modelData.body !== ""
                  text: row.modelData.body
                  color: Qt.darker(Color.foreground, 1.15)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                }

                Text {
                  width: parent.width
                  text: {
                    var parts = []
                    var time = panel.formatTime(row.modelData.time)
                    if (time !== "") parts.push(time)
                    if (panel.multiTopic && row.modelData.topic !== "") parts.push(row.modelData.topic)
                    var tags = panel.tagText(row.modelData)
                    if (tags !== "") parts.push(tags)
                    return parts.join("  ·  ")
                  }
                  visible: text !== ""
                  color: Qt.darker(Color.foreground, 1.7)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: row.modelData.click !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (row.modelData.click !== "") panel.openUrl(row.modelData.click)
              }
            }
          }
        }
      }

      Text {
        visible: panel.messages.length === 0
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(80)
        text: panel.configured ? "No messages yet" : "Set a topic to start receiving messages"
        color: Qt.darker(Color.foreground, 1.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
      }
    }
  }

  readonly property real listHeight: {
    if (panel.messages.length === 0) return 0
    // Leave room for the settings form when it is open; otherwise give the
    // messages most of the panel. The Flickable scrolls either way.
    var cap = panel.settingsOpen ? Style.space(260) : Style.space(440)
    return Math.min(cap, Math.max(Style.space(40), listColumn.implicitHeight))
  }
}
