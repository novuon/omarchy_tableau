import QtQuick
import qs.Commons

// A setup drawn at thumbnail size: one framed screen per workspace, split
// into the columns and rows that setup asks for.
//
// This is the shape the *config* asks for, not a promise about pixels: a
// narrow screen folds columns together at load time. Drawn from the same
// weights the loader uses, so a thumbnail can never drift from the setup it
// claims to show.
Row {
  id: root

  property var layout: []          // [{ number, columns: [{ w, h: [...] }] }]
  property color foreground: Color.foreground
  property color accent: Color.accent
  property bool highlight: false   // the loaded setup, drawn in accent
  property real screenHeight: Style.space(22)

  readonly property real screenWidth: Math.round(screenHeight * 1.55)
  readonly property color tint: highlight ? accent : foreground

  spacing: Style.space(4)

  Repeater {
    model: root.layout

    delegate: Rectangle {
      id: screen
      required property var modelData

      width: root.screenWidth
      height: root.screenHeight
      radius: Math.max(2, Style.cornerRadius)
      color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.05)
      border.width: 1
      border.color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.highlight ? 0.5 : 0.28)

      Item {
        id: inner
        anchors.fill: parent
        anchors.margins: Math.max(1, Math.round(root.screenHeight * 0.09))

        readonly property var cols: screen.modelData && screen.modelData.columns ? screen.modelData.columns : []
        readonly property real gap: 2
        readonly property real weightSum: {
          var total = 0
          for (var i = 0; i < cols.length; i++) total += Math.max(0.1, cols[i].w || 1)
          return total > 0 ? total : 1
        }

        Row {
          anchors.fill: parent
          spacing: inner.gap

          Repeater {
            model: inner.cols

            delegate: Column {
              id: column
              required property var modelData

              readonly property var heights: modelData && modelData.h && modelData.h.length ? modelData.h : [1]
              readonly property real heightSum: {
                var total = 0
                for (var i = 0; i < heights.length; i++) total += Math.max(0.1, heights[i] || 1)
                return total > 0 ? total : 1
              }

              width: Math.max(2, (inner.width - inner.gap * (inner.cols.length - 1))
                                 * Math.max(0.1, (modelData ? modelData.w : 1) || 1) / inner.weightSum)
              height: inner.height
              spacing: inner.gap

              Repeater {
                model: column.heights

                delegate: Rectangle {
                  required property var modelData

                  width: column.width
                  height: Math.max(2, (column.height - inner.gap * (column.heights.length - 1))
                                      * Math.max(0.1, modelData || 1) / column.heightSum)
                  radius: 1
                  color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.highlight ? 0.75 : 0.38)

                  Behavior on color { ColorAnimation { duration: 160 } }
                }
              }
            }
          }
        }
      }

      // Nothing configured on this workspace: an empty frame reads better
      // than a frame with one full-bleed block in it.
      Text {
        anchors.centerIn: parent
        visible: inner.cols.length === 0
        text: "·"
        color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.5)
        font.pixelSize: Style.font.caption
      }
    }
  }
}
