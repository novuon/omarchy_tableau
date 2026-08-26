import QtQuick
import qs.Commons

// One row in the setups menu.
//
// Not a Ui/Button on purpose: that centres its label and brings its own
// padding, so a column of them would line up with neither the header above
// nor the separators between. Here every row shares the panel's content edge
// and one height, and the hover highlight bleeds slightly past that edge so it
// reads as a menu rather than a stack of buttons.
Item {
  id: root

  property string label: ""
  property string detail: ""
  property string glyph: ""
  property bool current: false
  property bool hasCursor: false
  property bool destructive: false
  property bool enabledRow: true
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal clicked()

  readonly property bool hot: mouse.containsMouse && root.enabledRow

  implicitHeight: Style.space(26)
  height: implicitHeight
  opacity: enabledRow ? 1 : 0.4

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: -Style.space(6)
    anchors.rightMargin: -Style.space(6)
    radius: Style.cornerRadius
    color: root.hasCursor
           ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)
           : root.hot
           ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
           : "transparent"
  }

  // The mark for "this is what is loaded" is a dot, not a colour: colour
  // alone is the one signal a themed bar cannot be trusted to carry.
  Text {
    id: mark
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(14)
    text: root.current ? "•" : (root.glyph !== "" ? root.glyph : "")
    textFormat: Text.PlainText
    color: root.current ? root.accent : Qt.darker(root.foreground, 1.6)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Text {
    anchors.left: mark.right
    anchors.right: detailText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.destructive ? Color.urgent : root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Text {
    id: detailText
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: root.detail
    textFormat: Text.PlainText
    color: Qt.darker(root.foreground, 1.9)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
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
