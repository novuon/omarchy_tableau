import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Tableau: a project's whole desk -- workspaces, windows, services -- behind
// one click in the bar.
//
// The panel is a menu, not a dashboard. Picking a setup is the only thing most
// days need, so the cards sit at the top under one hero line saying what is
// loaded and on which screens. Each card carries a thumbnail of the desk it
// builds, because a setup is recognised by its shape long before its name is
// read. Saving is a separate, deliberate act at the bottom, never something
// that happens on its own.
Panel {
  id: root

  moduleName: "novuon.tableau"
  ipcTarget: "novuon.tableau"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color dimmer: Qt.darker(foreground, 2.2)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Naming a setup happens inline rather than in a dialog: it is one short
  // string, and a dialog here would be a second window to dismiss.
  property bool naming: false
  property string namingMode: "save"
  property string namingSource: ""
  property int cursorIndex: 0
  property string pendingDelete: ""
  readonly property int setupRowCount: SetupsStore.setups.length + 3

  function moveCursor(dy) {
    cursorIndex = Math.max(0, Math.min(root.setupRowCount - 1, cursorIndex + dy))
  }

  function activateCursor() {
    if (root.cursorIndex === 0) { SetupsStore.load("Empty", false); root.close(); return }
    var setupIndex = root.cursorIndex - 1
    if (setupIndex < SetupsStore.setups.length) {
      SetupsStore.load(SetupsStore.setups[setupIndex].name, false); root.close(); return
    }
    if (setupIndex === SetupsStore.setups.length) { root.namingMode = "save"; root.namingSource = ""; root.naming = true; return }
    if (SetupsStore.configExists) SetupsStore.edit(); else SetupsStore.createConfig()
    root.close()
  }

  function deleteCursor() {
    var i = root.cursorIndex - 1
    if (i >= 0 && i < SetupsStore.setups.length) {
      root.pendingDelete = SetupsStore.setups[i].name
      deleteConfirm.opened = true
    }
  }

  function beginNaming(mode) {
    var i = root.cursorIndex - 1
    if (i < 0 || i >= SetupsStore.setups.length) return
    root.namingMode = mode
    root.namingSource = SetupsStore.setups[i].name
    root.naming = true
  }

  readonly property string iconLoading: ""   // arrows-rotate, spun while busy
  readonly property string iconEmpty: ""     // empty square: the bare desktop
  readonly property string iconSave: ""      // floppy
  readonly property string iconEdit: ""      // pencil
  readonly property string iconCreate: ""    // plus

  readonly property color barIconColor: {
    if (SetupsStore.busy) return accent
    if (SetupsStore.hasProblem) return urgent
    return barForeground
  }

  readonly property int barContentWidth: Style.bar.iconFont
  readonly property int barSlot: barContentWidth + Style.space(10)
  readonly property real openPanelIndicatorWidth: barContentWidth
  readonly property real openPanelIndicatorHeight: barContentWidth
  implicitWidth: bar && bar.vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  function applySettings() {
    SetupsStore.fontFamily = root.fontFamily
  }
  onSettingsChanged: root.applySettings()
  Component.onCompleted: root.applySettings()

  onOpenedChanged: {
    if (!opened) {
      root.naming = false
      return
    }
    // Start the keyboard cursor on the loaded setup. Starting on Empty while
    // another setup is current made two cards appear highlighted on open.
    root.cursorIndex = SetupsStore.cursorIndexForCurrent()
    root.pendingDelete = ""
    SetupsStore.refresh()
  }

  onNamingChanged: {
    if (naming) {
      nameField.text = root.namingMode === "save"
                       ? (SetupsStore.current === "Empty" ? "" : SetupsStore.current)
                       : ""
      nameField.forceActiveFocus()
      nameField.selectAll()
    } else {
      keyCatcher.forceActiveFocus()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barSlot
    opticalSize: root.barContentWidth
    tooltipText: SetupsStore.plain(SetupsStore.tooltip)

    iconComponent: Component {
      Item {
        TableauIcon {
          anchors.centerIn: parent
          color: root.barIconColor

          // Keep the layout mark upright. Loading is communicated by the
          // progress line below and the panel status, not by rotating the mark.
        }

        // How far along it is, as a hairline under the glyph.
        Rectangle {
          visible: SetupsStore.busy && SetupsStore.total > 0
          anchors.bottom: parent.bottom
          anchors.bottomMargin: -Math.round(height * 1.5)
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.round(parent.width * 0.85)
          height: Math.max(2, Math.round(parent.height * 0.08))
          radius: height / 2
          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.22)

          Rectangle {
            height: parent.height
            radius: parent.radius
            color: root.accent
            width: SetupsStore.total > 0
                   ? Math.max(0, Math.min(1, SetupsStore.done / SetupsStore.total)) * parent.width
                   : 0
            Behavior on width { NumberAnimation { duration: 250 } }
          }
        }
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) SetupsStore.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher

    readonly property int desiredWidth: Style.space(340)
    contentWidth: Math.min(desiredWidth,
                           panel.availableCardWidth > 0 ? panel.availableCardWidth : desiredWidth)
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      // This component bakes in vim navigation -- j/k/l/h move, x deletes --
      // all checked before the plain-text fallback, so typing a setup name
      // under it is impossible. While naming, the field owns the keyboard.
      blocked: root.naming

      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.deleteCursor()
      onTextKey: function(t) { if (t === "r") SetupsStore.refresh() }

      onCloseRequested: {
        if (root.naming) root.naming = false
        else root.close()
      }

      Flickable {
        id: mainScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: mainColumn
          width: mainScroll.width
          spacing: 0

          // --- hero -----------------------------------------------------

          Item {
            width: parent.width
            height: Style.space(38)

            Rectangle {
              id: heroTile
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(30)
              height: width
              radius: Math.max(2, Style.cornerRadius)
              color: SetupsStore.hasProblem
                     ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.12)
                     : Qt.rgba(root.accent.r, root.accent.g, root.accent.b,
                               SetupsStore.busy ? 0.18 : 0.10)
              border.width: 1
              border.color: SetupsStore.hasProblem
                            ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.5)
                            : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.4)

              Behavior on color { ColorAnimation { duration: 160 } }

              TableauIcon {
                anchors.centerIn: parent
                width: Style.space(22)
                height: width
                color: SetupsStore.hasProblem ? root.urgent : root.accent

              }
            }

            Column {
              anchors.left: heroTile.right
              anchors.leftMargin: Style.space(12)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: SetupsStore.plain(SetupsStore.headline)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: SetupsStore.hasProblem ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                width: parent.width
                visible: text !== ""
                // Not upper-cased: this line often carries a monitor name,
                // and "EDP-1" is not what that connector is called.
                text: SetupsStore.plain(SetupsStore.subline)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: SetupsStore.hasProblem ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
              }
            }
          }

          // Progress, while a switch is running.
          Rectangle {
            width: parent.width
            visible: SetupsStore.busy
            height: visible ? Style.space(3) : 0
            radius: height / 2
            clip: true
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)

            Rectangle {
              visible: SetupsStore.total > 0
              height: parent.height
              radius: parent.radius
              color: root.accent
              width: SetupsStore.total > 0
                     ? Math.max(0, Math.min(1, SetupsStore.done / SetupsStore.total)) * parent.width
                     : 0
              Behavior on width { NumberAnimation { duration: 250 } }
            }

            // Teardown has nothing to count -- it is one dispatch and then a
            // wait -- so that half of the switch sweeps instead of filling.
            Rectangle {
              id: sweep
              visible: SetupsStore.busy && SetupsStore.total === 0
              width: Math.round(parent.width * 0.3)
              height: parent.height
              radius: parent.radius
              color: root.accent
              opacity: 0.85

              XAnimator on x {
                running: sweep.visible
                from: -sweep.width
                to: sweep.parent ? sweep.parent.width : 0
                duration: 1200
                loops: Animation.Infinite
                easing.type: Easing.InOutQuad
              }
            }
          }

          Item { width: 1; height: SetupsStore.busy ? Style.space(10) : Style.space(4) }

          // --- windows that refused to close ---------------------------

          Column {
            width: parent.width
            visible: SetupsStore.isBlocked
            spacing: Style.space(2)
            bottomPadding: visible ? Style.space(6) : 0

            Repeater {
              model: SetupsStore.isBlocked ? SetupsStore.blocked : []

              Text {
                width: parent.width
                text: "· " + SetupsStore.plain(modelData.title || modelData["class"])
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          MenuRow {
            width: parent.width
            visible: SetupsStore.isBlocked
            label: "Close Them Anyway"
            destructive: true
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: {
              forceConfirm.opened = true
            }
          }

          MenuRow {
            width: parent.width
            visible: SetupsStore.isBlocked || SetupsStore.phase === "error"
            label: SetupsStore.phase === "error" ? "Retry last load" : "Dismiss"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: SetupsStore.phase === "error" ? SetupsStore.retry(false) : SetupsStore.clearProblem()
          }

          MenuRow {
            width: parent.width
            visible: SetupsStore.isBlocked
            label: "Dismiss"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: SetupsStore.clearProblem()
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
            visible: SetupsStore.isBlocked || SetupsStore.phase === "error"
          }

          // --- the setups ----------------------------------------------

          PanelSectionHeader {
            width: parent.width
            text: "Tableau"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bottomPadding: Style.space(4)
          }

          // Always first, always present: the way back to a bare Omarchy
          // desktop is not something you should have to configure.
          SetupCard {
            width: parent.width
            label: "Empty desktop"
            glyph: root.iconEmpty
            meta: "closes everything, stops services"
            layout: [{ number: 1, columns: [] }]
            current: SetupsStore.current === "Empty"
            hasCursor: root.cursorIndex === 0
            enabledRow: !SetupsStore.busy && !SetupsStore.actionBusy && !SetupsStore.isBlocked
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: {
              SetupsStore.load("Empty", false)
              root.close()
            }
          }

          Repeater {
            model: SetupsStore.setups

            SetupCard {
              width: mainColumn.width
              label: modelData.name
              glyph: modelData.icon && modelData.icon !== "" ? modelData.icon : SetupsStore.iconSetups
              meta: SetupsStore.metaFor(modelData)
              layout: modelData.layout || []
              current: SetupsStore.current === modelData.name
              hasCursor: root.cursorIndex === index + 1
              enabledRow: !SetupsStore.busy && !SetupsStore.actionBusy && !SetupsStore.isBlocked
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                SetupsStore.load(modelData.name, false)
                root.close()
              }
            }
          }

          Text {
            width: parent.width
            visible: SetupsStore.loaded && SetupsStore.setups.length === 0
                     && SetupsStore.configError === ""
            topPadding: visible ? Style.space(4) : 0
            bottomPadding: visible ? Style.space(4) : 0
            text: SetupsStore.configExists
                  ? "No setups defined yet. Arrange a desk you like, then save it."
                  : "No setups file yet."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            width: parent.width
            visible: root.cursorIndex > 0 && root.cursorIndex <= SetupsStore.setups.length
            spacing: Style.space(8)
            topPadding: visible ? Style.space(6) : 0

            Button {
              width: (parent.width - Style.space(16)) / 3
              text: "Rename"
              bordered: true
              leftAlign: true
              enabled: !SetupsStore.busy && !SetupsStore.actionBusy
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.beginNaming("rename")
            }
            Button {
              width: (parent.width - Style.space(16)) / 3
              text: "Duplicate"
              bordered: true
              leftAlign: true
              enabled: !SetupsStore.busy && !SetupsStore.actionBusy
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.beginNaming("duplicate")
            }
            Button {
              width: (parent.width - Style.space(16)) / 3
              text: "Delete"
              bordered: true
              leftAlign: true
              enabled: !SetupsStore.busy && !SetupsStore.actionBusy
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.deleteCursor()
            }
          }

          Item { width: 1; height: Style.space(8) }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // --- saving ---------------------------------------------------

          Row {
            id: actions
            width: parent.width
            visible: !root.naming
            topPadding: Style.space(8)
            spacing: Style.space(8)

            readonly property real saveWidth: Math.round((width - Style.space(8)) * 0.62)

            Button {
              width: actions.saveWidth
              text: "Save Current State"
              iconText: root.iconSave
              bordered: true
              leftAlign: true
              enabled: !SetupsStore.busy && !SetupsStore.actionBusy
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: { root.namingMode = "save"; root.namingSource = ""; root.naming = true }
            }

            Button {
              width: actions.width - Style.space(8) - actions.saveWidth
              text: SetupsStore.configExists ? "Edit" : "Create"
              iconText: SetupsStore.configExists ? root.iconEdit : root.iconCreate
              bordered: true
              leftAlign: true
              enabled: !SetupsStore.busy && !SetupsStore.actionBusy
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                if (SetupsStore.configExists) SetupsStore.edit()
                else SetupsStore.createConfig()
                root.close()
              }
            }
          }

          Column {
            width: parent.width
            visible: root.naming
            spacing: Style.space(4)
            topPadding: visible ? Style.space(8) : 0
            bottomPadding: visible ? Style.space(4) : 0

            TextField {
              id: nameField
              width: parent.width
              placeholderText: "Name this setup"
              foreground: root.foreground
              accent: root.accent
              // Consume Enter at the text field. If it bubbles to
              // PanelKeyCatcher after `root.naming` is cleared, the active
              // setup's cursor is activated too; for Save Current State that
              // means closing the live desk and loading it again.
              Keys.onPressed: function(event) {
                if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return
                event.accepted = true
                if (root.namingMode === "rename") SetupsStore.renameSetup(root.namingSource, text)
                else if (root.namingMode === "duplicate") SetupsStore.duplicateSetup(root.namingSource, text)
                else SetupsStore.saveCurrent(text)
                root.naming = false
                root.close()
              }
              Keys.onEscapePressed: root.naming = false
            }

            Text {
              width: parent.width
              text: "Saves the windows open right now, in the columns they are in."
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }

    ConfirmDialog {
      id: forceConfirm
      anchors.fill: parent
      z: 10
      message: "Close these windows anyway? Anything they were asking about is lost."
      confirmText: "Close them"
      cancelText: "Leave them open"
      fontFamily: root.fontFamily
      onConfirmed: {
        SetupsStore.load(SetupsStore.current, true)
        forceConfirm.opened = false
        root.close()
      }
      onCanceled: forceConfirm.opened = false
    }

    ConfirmDialog {
      id: deleteConfirm
      anchors.fill: parent
      z: 11
      message: "Delete “" + root.pendingDelete + "”? This cannot be undone from the menu."
      confirmText: "Delete"
      cancelText: "Keep it"
      fontFamily: root.fontFamily
      onConfirmed: {
        SetupsStore.deleteSetup(root.pendingDelete)
        root.pendingDelete = ""
        deleteConfirm.opened = false
      }
      onCanceled: { root.pendingDelete = ""; deleteConfirm.opened = false }
    }
  }
}
