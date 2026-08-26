import QtQuick
import qs.Commons

// One setup in the menu: what it is called, what it opens, and a thumbnail
// of the desk it builds.
//
// A card rather than a text row because the thumbnail is the point — you
// pick a setup by recognising its shape long before you finish reading its
// name. The loaded one is marked three ways (accent bar, accent thumbnail,
// bold name), since colour alone is the one signal a themed bar cannot be
// trusted to carry.
Item {
  id: root

  property string label: ""
  property string meta: ""
  property string glyph: ""
  property var layout: []
  property bool current: false
  property bool hasCursor: false
  property bool enabledRow: true
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal clicked()

  readonly property bool hot: mouse.containsMouse && root.enabledRow

  implicitHeight: Style.space(42)
  height: implicitHeight
  opacity: enabledRow ? 1 : 0.4

  Behavior on opacity { NumberAnimation { duration: 120 } }

  // The fill bleeds past the panel's content edge so a hovered card reads as
  // a menu selection rather than a floating tile.
  Rectangle {
    id: fill
    anchors.fill: parent
    anchors.leftMargin: -Style.space(6)
    anchors.rightMargin: -Style.space(6)
    radius: Math.max(2, Style.cornerRadius)
    color: root.current
           ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.hot ? 0.18 : 0.12)
           : (root.hasCursor
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
              : (root.hot ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                         : "transparent"))

    Behavior on color { ColorAnimation { duration: 140 } }

    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(2)
      height: Math.round(parent.height * 0.6)
      radius: width / 2
      visible: root.current || root.hot || root.hasCursor
      color: root.current ? root.accent : root.foreground
      opacity: root.current ? 1 : 0.35
      Behavior on opacity { NumberAnimation { duration: 140 } }
    }
  }

  Rectangle {
    id: tile
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(26)
    height: width
    radius: Math.max(2, Style.cornerRadius)
    color: root.current
           ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
           : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, root.hasCursor ? 0.10 : 0.06)
    border.width: 1
    border.color: root.current
                  ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, root.hasCursor ? 0.35 : 0.18)

    Behavior on color { ColorAnimation { duration: 140 } }

    Text {
      anchors.centerIn: parent
      text: root.glyph
      textFormat: Text.PlainText
      color: root.current ? root.accent : Qt.darker(root.foreground, 1.3)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  LayoutPreview {
    id: preview
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    layout: root.layout
    foreground: root.foreground
    accent: root.accent
    highlight: root.current
    screenHeight: Style.space(22)
    opacity: root.hot || root.current ? 1 : 0.75
    Behavior on opacity { NumberAnimation { duration: 140 } }
  }

  Column {
    anchors.left: tile.right
    anchors.leftMargin: Style.space(10)
    anchors.right: preview.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    Text {
      width: parent.width
      text: root.label
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: root.current
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: root.meta
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Qt.darker(root.foreground, 1.9)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabledRow
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
