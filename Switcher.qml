import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property var windows: []
  property int selectedIndex: 0
  property int pendingSteps: 0
  property bool queryWanted: false
  property var targetScreen: null
  property bool destroying: false
  property string bindingOwner: ""

  readonly property int cardWidth: Style.space(260)
  readonly property int cardHeight: Style.space(176)
  readonly property int cardSpacing: Style.space(12)
  readonly property int trackPadding: Style.space(16)

  function normalizeAddress(value) {
    var address = String(value || "").toLowerCase()
    if (!address) return ""
    if (address.indexOf("0x") !== 0) address = "0x" + address
    return /^0x[0-9a-f]+$/.test(address) ? address : ""
  }

  function focusedScreen() {
    var monitorName = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; ++i) {
      if (String(screens[i].name || "") === monitorName)
        return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  function snapshotWindows(clients) {
    if (!Array.isArray(clients)) return []

    var toplevelByAddress = ({})
    var toplevels = Hyprland.toplevels && Hyprland.toplevels.values
      ? Hyprland.toplevels.values : []

    for (var i = 0; i < toplevels.length; ++i) {
      var top = toplevels[i]
      var topAddress = normalizeAddress(top.address)
      if (topAddress) toplevelByAddress[topAddress] = top
    }

    var rows = []
    for (var j = 0; j < clients.length; ++j) {
      var client = clients[j]
      if (!client || client.mapped === false || client.hidden === true) continue

      var workspaceId = Number(client.workspace ? client.workspace.id : -1)
      if (workspaceId <= 0) continue

      var address = normalizeAddress(client.address)
      if (!address) continue

      var focusHistoryId = Number(client.focusHistoryID)
      if (!Number.isFinite(focusHistoryId) || focusHistoryId < 0)
        focusHistoryId = 2147483647

      var topLevel = toplevelByAddress[address] || null
      var wayland = topLevel ? (topLevel.wayland || null) : null
      var appClass = String(client.class || client.initialClass || (wayland ? wayland.appId || "" : "") || "Application")
      var title = String(client.title || (topLevel ? topLevel.title || "" : "") || appClass)

      rows.push({
        address: address,
        title: title,
        appClass: appClass,
        focusHistoryId: focusHistoryId,
        previewWidth: Array.isArray(client.size) ? Number(client.size[0]) || 16 : 16,
        previewHeight: Array.isArray(client.size) ? Number(client.size[1]) || 9 : 9,
        wayland: wayland
      })
    }

    rows.sort(function(a, b) {
      return a.focusHistoryId - b.focusHistoryId
    })

    return rows
  }

  function cycle(direction) {
    if (opened && windows.length > 0) {
      select(direction)
      return
    }

    if (!queryWanted)
      targetScreen = focusedScreen()
    pendingSteps += direction
    queryWanted = true
    if (!clientsQuery.running)
      clientsQuery.running = true
  }

  function select(direction) {
    if (windows.length === 0) return
    selectedIndex = (selectedIndex + direction + windows.length) % windows.length
    Qt.callLater(function() {
      listView.positionViewAtIndex(selectedIndex, ListView.Contain)
    })
  }

  function cancel() {
    opened = false
    windows = []
    pendingSteps = 0
    queryWanted = false
  }

  function commit() {
    if (!opened || selectedIndex < 0 || selectedIndex >= windows.length) {
      cancel()
      return
    }

    var address = windows[selectedIndex].address
    cancel()

    if (address)
      Qt.callLater(function() {
        Quickshell.execDetached([
          "hyprctl", "eval",
          'hl.dispatch(hl.dsp.focus({ window = "address:' + address + '" }))'
        ])
      })
  }

  function finishWindowQuery(text) {
    if (!queryWanted) return

    var clients
    try {
      clients = JSON.parse(String(text || "[]"))
    } catch (error) {
      console.warn("omarchy-switcher: failed to parse hyprctl clients:", error)
      pendingSteps = 0
      queryWanted = false
      return
    }

    var nextWindows = snapshotWindows(clients)
    if (nextWindows.length < 2) {
      pendingSteps = 0
      queryWanted = false
      return
    }

    windows = nextWindows

    var steps = pendingSteps
    pendingSteps = 0
    queryWanted = false
    selectedIndex = ((steps % windows.length) + windows.length) % windows.length

    opened = true
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      listView.positionViewAtIndex(selectedIndex, ListView.Contain)
    })
  }

  function bindingScript() {
    var owner = bindingOwner
    return [
      'hl.unbind("SUPER + TAB")',
      'hl.unbind("SUPER + SHIFT + TAB")',
      'hl.unbind("SUPER + SUPER_L")',
      'hl.unbind("SUPER + SUPER_R")',
      'hl.bind("SUPER + TAB", hl.dsp.global("org.lsong.window-switcher:next"), { repeating = true, description = "Switcher next window" })',
      'hl.bind("SUPER + SHIFT + TAB", hl.dsp.global("org.lsong.window-switcher:previous"), { repeating = true, description = "Switcher previous window" })',
      'hl.bind("SUPER + SUPER_L", hl.dsp.global("org.lsong.window-switcher:commit"), { release = true, description = "Switcher commit" })',
      'hl.bind("SUPER + SUPER_R", hl.dsp.global("org.lsong.window-switcher:commit"), { release = true, description = "Switcher commit" })',
      '_G.lsongWindowSwitcherBindingOwner = "' + owner + '"'
    ].join("; ")
  }

  function applyBindings() {
    if (destroying) return
    bindingOwner = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2)
    Quickshell.execDetached(["hyprctl", "eval", bindingScript()])
  }

  function restoreBindings() {
    if (!bindingOwner) return

    var owner = bindingOwner
    var script = [
      'if _G.lsongWindowSwitcherBindingOwner == "' + owner + '" then',
      '_G.lsongWindowSwitcherBindingOwner = nil',
      'hl.unbind("SUPER + TAB")',
      'hl.unbind("SUPER + SHIFT + TAB")',
      'hl.unbind("SUPER + SUPER_L")',
      'hl.unbind("SUPER + SUPER_R")',
      'hl.bind("SUPER + TAB", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })',
      'hl.bind("SUPER + SHIFT + TAB", hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })',
      'end'
    ].join("; ")

    Quickshell.execDetached(["hyprctl", "eval", script])
  }

  Component.onCompleted: {
    targetScreen = focusedScreen()
    applyBindings()
  }

  Component.onDestruction: {
    destroying = true
    restoreBindings()
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (event && event.name === "configreloaded")
        rebindTimer.restart()
    }
  }

  Timer {
    id: rebindTimer
    interval: 500
    repeat: false
    onTriggered: root.applyBindings()
  }

  Process {
    id: clientsQuery
    command: ["hyprctl", "clients", "-j"]
    running: false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishWindowQuery(text)
    }
  }

  GlobalShortcut {
    appid: "org.lsong.window-switcher"
    name: "next"
    description: "Open or advance the window switcher"
    onPressed: root.cycle(1)
  }

  GlobalShortcut {
    appid: "org.lsong.window-switcher"
    name: "previous"
    description: "Open or move backward in the window switcher"
    onPressed: root.cycle(-1)
  }

  GlobalShortcut {
    appid: "org.lsong.window-switcher"
    name: "commit"
    description: "Activate the selected window"
    onPressed: root.commit()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    onVisibleChanged: {
      if (visible) keyCatcher.forceActiveFocus()
    }
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "omarchy-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Qt.alpha(Color.background, 0.28)
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.cancel()
          event.accepted = true
        }
      }
      Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Meta
            || event.key === Qt.Key_Super_L
            || event.key === Qt.Key_Super_R) {
          root.commit()
          event.accepted = true
        }
      }
    }

    BorderSurface {
      id: track
      anchors.centerIn: parent
      width: Math.min(
        panel.width - Style.space(80),
        Math.max(
          root.cardWidth + track.contentLeftInset + track.contentRightInset,
          root.windows.length * root.cardWidth
            + Math.max(0, root.windows.length - 1) * root.cardSpacing
            + track.contentLeftInset + track.contentRightInset
        )
      )
      // Leave room below the cards so ListView's clip does not cut off their bottom border.
      height: root.cardHeight + root.trackPadding * 2 + Math.max(2, Style.normalBorderWidth)
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec(
        "menu",
        "border",
        Color.menu.border,
        Math.max(1, Style.normalBorderWidth)
      )
      padding: root.trackPadding

      ListView {
        id: listView
        anchors.fill: parent
        anchors.topMargin: track.contentTopInset
        anchors.rightMargin: track.contentRightInset
        anchors.bottomMargin: track.contentBottomInset
        anchors.leftMargin: track.contentLeftInset
        orientation: ListView.Horizontal
        spacing: root.cardSpacing
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.windows
        currentIndex: root.selectedIndex

        delegate: Rectangle {
          id: card
          required property int index
          required property var modelData

          width: root.cardWidth
          height: root.cardHeight
          radius: Style.cornerRadius
          color: index === root.selectedIndex
            ? Color.menu.selectedBackground
            : Qt.alpha(Color.menu.text, 0.04)
          border.width: Math.max(1, Style.normalBorderWidth)
          border.color: index === root.selectedIndex ? Color.accent : Color.menu.border
          clip: true

          Rectangle {
            id: previewFrame
            anchors {
              top: parent.top
              left: parent.left
              right: parent.right
              bottom: titleBar.top
              margins: Style.space(7)
              bottomMargin: Style.space(5)
            }
            radius: Math.max(2, Style.cornerRadius - Style.space(3))
            color: Qt.alpha(Color.menu.text, 0.05)
            clip: true

            Text {
              anchors.centerIn: parent
              width: parent.width - Style.space(20)
              text: card.modelData.appClass
              color: Color.menu.text
              opacity: preview.hasContent ? 0 : 0.55
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            ScreencopyView {
              id: preview
              anchors.fill: parent
              captureSource: root.opened && card.modelData.wayland
                ? card.modelData.wayland : null
              paintCursor: false
              live: false
              constraintSize: Qt.size(Math.max(1, width), Math.max(1, height))
              opacity: hasContent ? 1 : 0
            }
          }

          Rectangle {
            id: titleBar
            anchors {
              left: parent.left
              right: parent.right
              bottom: parent.bottom
              leftMargin: card.border.width
              rightMargin: card.border.width
              bottomMargin: card.border.width
            }
            height: Style.space(34)
            color: index === root.selectedIndex
              ? Qt.alpha(Color.accent, 0.14)
              : "transparent"

            Text {
              anchors {
                left: parent.left
                right: parent.right
                leftMargin: Style.space(9)
                rightMargin: Style.space(9)
                verticalCenter: parent.verticalCenter
              }
              text: card.modelData.title
              color: index === root.selectedIndex
                ? Color.menu.selectedText
                : Color.menu.text
              elide: Text.ElideRight
              maximumLineCount: 1
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
