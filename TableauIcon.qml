import QtQuick

// A compact map of one workspace: a wide terminal on the left, and two
// stacked terminals on the right. One antialiased path keeps the fine line
// weight clean, while the small gaps separate each terminal like the real
// desktop layout.
Item {
  id: root

  property color color: "white"
  // The Omarchy Workspaces mark is a small, light line glyph. Keep Tableau
  // optically comparable instead of letting the pane outlines dominate.
  property real stroke: 0.7

  implicitWidth: 17
  implicitHeight: 17

  Canvas {
    id: mark
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.strokeStyle = root.color
      ctx.lineWidth = root.stroke
      ctx.lineJoin = "round"
      ctx.lineCap = "round"

      // Give the three panes a little more breathing room inside the mark,
      // matching the compact, inset feel of Omarchy's workspace glyph.
      var inset = root.stroke / 2 + 1.8
      var right = width - inset
      var bottom = height - inset
      var splitX = inset + (right - inset) * 1 / 2
      var splitY = inset + (bottom - inset) * 2 / 3
      // Leave a visible breathing gap between terminal panes, like the
      // spacing between tiled windows on the desktop.
      var gap = Math.max(2.0, width * 0.12)

      ctx.beginPath()
      // Left terminal: full height, wide column.
      ctx.rect(inset, inset, splitX - gap / 2 - inset, bottom - inset)
      // Right column: two terminals with a matching horizontal gap.
      ctx.rect(splitX + gap / 2, inset,
               right - splitX - gap / 2, splitY - gap / 2 - inset)
      ctx.rect(splitX + gap / 2, splitY + gap / 2,
               right - splitX - gap / 2, bottom - splitY - gap / 2)
      ctx.stroke()
    }

    Connections {
      target: root
      function onColorChanged() { mark.requestPaint() }
      function onStrokeChanged() { mark.requestPaint() }
    }
  }
}
