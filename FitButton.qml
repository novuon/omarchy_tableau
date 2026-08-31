import QtQuick
import qs.Ui
import qs.Commons

// Tableau action button with a bounded label. The shared Button intentionally
// sizes itself to its natural text width; panel actions have a fixed column,
// so long labels need to adapt instead of bleeding into their neighbour.
Button {
  id: root

  property real minimumFontSize: Style.font.caption

  clip: true
  tooltipText: labelMetrics.width > availableLabelWidth ? text : ""

  readonly property real availableLabelWidth:
    Math.max(1, width - horizontalPadding * 2
             - (iconText !== "" ? iconSize + Style.spacing.controlGap : 0))

  TextMetrics {
    id: labelMetrics
    text: root.text
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  fontSize: labelMetrics.width > root.availableLabelWidth
             ? Math.max(root.minimumFontSize,
                        Style.font.body * root.availableLabelWidth / labelMetrics.width)
             : Style.font.body
}
