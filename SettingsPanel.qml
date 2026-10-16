import QtQuick
import qs.Commons
import qs.Ui

// Settings popup, opened by right-clicking the workspaces. One section per
// connected screen: a live preview, a shape picker and the theme's colors.
// Every choice is saved straight away through the widget (`host`).
KeyboardPanel {
  id: panel

  property var host: null

  readonly property color textColor: Color.popups.text
  readonly property color mutedColor: Util.alpha(Color.popups.text, 0.6)
  readonly property real line: host ? host.line : 1
  readonly property real shapeSize: Math.round(Style.font.body * 1.6)

  centerOnBar: false
  focusTarget: keyCatcher
  contentWidth: panel.fittedContentWidth(Style.space(340))
  contentHeight: panel.fittedContentHeight(settingsColumn.implicitHeight)

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.close()

    Flickable {
      id: settingsScroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: settingsColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: settingsColumn
        width: settingsScroll.width
        spacing: Style.space(14)

        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            // Plain text only: titles and names come from other apps and must
            // never be parsed as rich text (an <img> would make the shell fetch it).
            textFormat: Text.PlainText
            text: "Workspace screens"
            color: panel.textColor
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Pick how each screen is drawn in the bar."
            color: panel.mutedColor
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        // App icons on or off for the whole widget.
        Row {
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: "App icons"
            color: panel.textColor
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Repeater {
            model: [{ label: "Show", value: true }, { label: "Hide", value: false }]

            Rectangle {
              id: appsOption
              required property var modelData
              readonly property bool selected: panel.host && panel.host.showApps === modelData.value

              anchors.verticalCenter: parent.verticalCenter
              width: appsLabel.implicitWidth + Style.space(16)
              height: appsLabel.implicitHeight + Style.space(8)
              radius: Style.space(4)
              color: selected ? Util.alpha(panel.textColor, 0.16)
                : (appsArea.containsMouse ? Util.alpha(panel.textColor, 0.08) : "transparent")
              border.width: 1
              border.color: selected ? panel.textColor : Util.alpha(panel.textColor, 0.12)

              Text {
                textFormat: Text.PlainText
                id: appsLabel
                anchors.centerIn: parent
                text: appsOption.modelData.label
                color: panel.textColor
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: appsArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.host.setShowApps(appsOption.modelData.value)
              }
            }
          }
        }

        Repeater {
          model: panel.host ? panel.host.screenRows() : []

          Column {
            id: screenSection
            required property var modelData

            width: settingsColumn.width
            spacing: Style.space(8)

            Rectangle {
              width: parent.width
              height: 1
              color: Util.alpha(panel.textColor, 0.1)
            }

            // Preview + screen name.
            Row {
              spacing: Style.space(10)

              ScreenShape {
                anchors.verticalCenter: parent.verticalCenter
                kind: screenSection.modelData.kind
                color: screenSection.modelData.color
                borderColor: panel.textColor
                filled: true
                label: "1"
                filledLabelColor: panel.host ? panel.host.contrastOn(screenSection.modelData.color) : "white"
                fontFamily: Style.font.family
                fontSize: Math.round(Style.font.body * 0.8)
                size: panel.shapeSize
                line: panel.line
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  textFormat: Text.PlainText
                  text: screenSection.modelData.title
                  color: panel.textColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  text: screenSection.modelData.port
                  color: panel.mutedColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }

            // Shape picker.
            Flow {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: panel.host ? panel.host.shapeKinds : []

                Rectangle {
                  id: shapeOption
                  required property var modelData
                  readonly property bool selected: screenSection.modelData.kind === modelData.kind

                  width: shapeOptionContent.implicitWidth + Style.space(12)
                  height: shapeOptionContent.implicitHeight + Style.space(8)
                  radius: Style.space(4)
                  color: selected ? Util.alpha(screenSection.modelData.color, 0.18)
                    : (shapeArea.containsMouse ? Util.alpha(panel.textColor, 0.08) : "transparent")
                  border.width: 1
                  border.color: selected ? screenSection.modelData.color : Util.alpha(panel.textColor, 0.12)

                  Row {
                    id: shapeOptionContent
                    anchors.centerIn: parent
                    spacing: Style.space(5)

                    ScreenShape {
                      anchors.verticalCenter: parent.verticalCenter
                      kind: shapeOption.modelData.kind
                      color: shapeOption.selected ? screenSection.modelData.color : panel.textColor
                      size: Math.round(panel.shapeSize * 0.8)
                      line: panel.line
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: shapeOption.modelData.name
                      color: panel.textColor
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }
                  }

                  MouseArea {
                    id: shapeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.host.setScreenChoice(screenSection.modelData.key, "shape", shapeOption.modelData.kind)
                  }
                }
              }
            }

            // Theme colors.
            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: panel.host ? panel.host.colorChoices() : []

                Rectangle {
                  id: swatch
                  required property var modelData
                  readonly property bool selected: screenSection.modelData.colorName === modelData.name

                  width: Math.round(Style.font.body * 1.6)
                  height: width
                  radius: width / 2
                  color: "transparent"
                  border.width: selected ? 2 : 0
                  border.color: panel.textColor

                  Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 6
                    height: width
                    radius: width / 2
                    color: swatch.modelData.color
                    scale: swatchArea.containsMouse && !swatch.selected ? 1.1 : 1
                    Behavior on scale { NumberAnimation { duration: 90 } }
                  }

                  MouseArea {
                    id: swatchArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.host.setScreenChoice(screenSection.modelData.key, "color", swatch.modelData.name)
                  }
                }
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(panel.textColor, 0.1)
        }

        Text {
          textFormat: Text.PlainText
          text: "Reset to defaults"
          color: resetArea.containsMouse ? panel.textColor : panel.mutedColor
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall

          MouseArea {
            id: resetArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.host.resetScreenChoices()
          }
        }
      }
    }
  }
}
