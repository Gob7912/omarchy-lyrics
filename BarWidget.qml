import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import qs.Ui
import qs.Commons
import qs.Commons as Commons

BarWidget {
  id: root
  moduleName: "gob7912.lyrics"

  function close() { popupOpen = false }
  readonly property bool opened: popupOpen

  LyricsService {
    id: lyrics
  }

  property bool popupOpen: false
  property real maxLabelWidth: 320
  property real widgetSpacing: Style.space(6)

  readonly property color widgetColor: root.bar ? root.bar.barForeground : Commons.Color.foreground
  readonly property color accentColor: Commons.Color.accent

  readonly property bool isBrowserOrYouTube: lyrics.fromBrowser || lyrics.isYouTube

  // If from browser / YouTube, ONLY show when synchronized lyrics are actually found!
  // If lyrics are not found on YouTube, do NOT show the video/track title (keep bar clean)
  readonly property bool hasContent: {
    if (!lyrics.isPlaying) return false
    if (isBrowserOrYouTube) {
      return lyrics.hasLyrics
    }
    return lyrics.hasLyrics || (lyrics.title !== "" && lyrics.status !== "notfound")
  }

  property bool showOffsetToast: false
  Timer {
    id: offsetToastTimer
    interval: 1400
    onTriggered: root.showOffsetToast = false
  }

  readonly property string targetLine: {
    if (showOffsetToast) return "Offset: " + (lyrics.offsetMs >= 0 ? "+" : "") + lyrics.offsetMs + " ms"
    if (lyrics.hasLyrics) {
      return lyrics.current !== "" ? lyrics.current : "♪ ~ ♪"
    }
    if (isBrowserOrYouTube) return ""
    if (lyrics.status === "loading") return "Loading lyrics..."
    if (lyrics.title !== "" && lyrics.status !== "notfound") return lyrics.title + (lyrics.artist ? " · " + lyrics.artist : "")
    return "♪ ~ ♪"
  }

  property string shown: ""
  property string previousText: ""
  property int typed: 0
  property int settled: 0
  property int targetTyped: 0
  property real scrollX: 0
  property bool typewriter: false
  property bool showCaret: false

  readonly property bool byWord: lyrics.hasLyrics && lyrics.wordTimed && lyrics.current !== ""
  readonly property int clipChars: byWord ? settled : typed
  readonly property real clipW: clipChars >= shown.length ? fullW : (clipChars === typed ? typedW : settledW)
  readonly property bool typing: clipChars < shown.length
  readonly property bool isLeftScrolled: (-curContainer.x > 4) || (root.scrollX > 4)

  Text {
    id: fullProbe
    visible: false
    text: root.shown
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
  }
  Text {
    id: typedProbe
    visible: false
    text: root.typed < root.shown.length ? root.shown.slice(0, root.typed) : ""
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
  }
  Text {
    id: settledProbe
    visible: false
    text: root.settled < root.shown.length ? root.shown.slice(0, root.settled) : ""
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
  }

  readonly property real fullW: fullProbe.implicitWidth
  readonly property real typedW: typed >= shown.length ? fullW : typedProbe.implicitWidth
  readonly property real settledW: settled >= shown.length ? fullW : settledProbe.implicitWidth
  readonly property real overflowW: Math.max(0, fullW - textBox.width)

  // Typewriter timer for smooth reveal (only used if typewriter: true)
  Timer {
    id: typer
    repeat: true
    interval: 20
    onTriggered: {
      if (root.typed < root.targetTyped) {
        var n = Math.min(root.shown.length, root.typed + 1)
        var c = root.shown.charCodeAt(n - 1)
        if (n < root.shown.length && c >= 0xD800 && c <= 0xDBFF) n++
        root.typed = n
      } else if (root.typed >= root.shown.length) {
        stop()
        if (root.overflowW > 0) startGlide()
      }
    }
  }

  function resetLine() {
    glide.stop()
    freshIn.stop()
    typer.stop()
    scrollX = 0
    previousText = ""
    shown = targetLine
    if (byWord) {
      var initial = Math.min(shown.length, lyrics.wordChars)
      settled = 0
      typed = initial
      if (initial > 0) freshIn.restart()
    } else {
      typed = shown.length
      settled = typed
    }
  }

  // Word-by-word and player switch listener
  Connections {
    target: lyrics
    function onPlayerChanged() {
      root.resetLine()
    }
    function onTrackKeyChanged() {
      root.resetLine()
    }
    function onWordCharsChanged() {
      if (!root.byWord) return
      var n = Math.min(root.shown.length, lyrics.wordChars)
      if (n > root.typed && root.visible) {
        root.settled = root.typed
        root.typed = n
        freshIn.restart()
      } else {
        freshIn.stop()
        root.typed = n
        root.settled = n
      }
      if (root.typed >= root.shown.length && root.overflowW > 0) {
        root.scrollX = root.overflowW
      }
    }
  }

  // Handle line change with smooth animation
  onTargetLineChanged: {
    previousText = shown
    shown = targetLine
    glide.stop()
    scrollX = 0
    freshIn.stop()
    typer.stop()

    if (byWord) {
      var initial = Math.min(shown.length, lyrics.wordChars)
      settled = 0
      typed = initial
      slide.restart()
      if (initial > 0) {
        freshIn.restart()
      }
      if (initial >= shown.length && overflowW > 0) {
        startGlide()
      }
      return
    }

    if (!typewriter) {
      typed = shown.length
      settled = typed
      slide.restart()
      if (overflowW > 0) {
        startGlide()
      }
      return
    }

    // Typewriter effect across the line duration (only when typewriter: true)
    typed = 0
    settled = 0
    targetTyped = shown.length
    var dur = Math.max(0.4, lyrics.lineEnd - lyrics.lineStart)
    typer.interval = Math.max(8, Math.min(26, (dur * 1000 * 0.35) / Math.max(1, shown.length)))
    typer.restart()
    slide.restart()
  }

  Component.onCompleted: {
    shown = targetLine
    typed = shown.length
    settled = typed
    targetTyped = typed
  }

  function startGlide() {
    if (root.overflowW <= 0) return
    var dur = Math.max(1.2, lyrics.lineEnd - lyrics.lineStart)
    glideMove.to = root.overflowW
    glideMove.duration = Math.max(1400, Math.min(8000, dur * 1000 * 0.55))
    glide.restart()
  }

  SequentialAnimation {
    id: glide
    PauseAnimation { duration: 650 }
    NumberAnimation {
      id: glideMove
      target: root
      property: "scrollX"
      to: root.overflowW
      duration: Math.max(1400, root.overflowW * 34)
      easing.type: Easing.InOutSine
    }
  }

  // Alpha mask item for smooth edge fading on left and right borders
  Item {
    id: maskItem
    width: Math.max(1, textBox.width)
    height: Math.max(1, textBox.height)
    visible: false
    layer.enabled: true

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop {
          position: 0.0
          color: root.isLeftScrolled ? "#00ffffff" : "#ffffffff"
        }
        GradientStop {
          position: root.isLeftScrolled ? Math.min(0.12, 18 / Math.max(1, textBox.width)) : 0.0
          color: "#ffffffff"
        }
        GradientStop {
          position: root.overflowW > 0 ? Math.max(0.85, 1.0 - (24 / Math.max(1, textBox.width))) : 1.0
          color: "#ffffffff"
        }
        GradientStop {
          position: 1.0
          color: root.overflowW > 0 ? "#00ffffff" : "#ffffffff"
        }
      }
    }
  }

  visible: hasContent
  implicitWidth: hasContent ? (row.implicitWidth + Style.space(16)) : 0
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: root.widgetSpacing

    // Album art thumbnail or music icon (Angel OS style)
    Item {
      id: noteItem
      width: Style.space(16)
      height: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter

      Image {
        id: barCover
        anchors.fill: parent
        source: lyrics.artUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready && lyrics.isPlaying
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: barCoverMask
        }
      }

      Rectangle {
        id: barCoverMask
        anchors.fill: parent
        radius: Style.cornerRadius
        visible: false
        layer.enabled: true
      }

      Text {
        id: iconGlyph
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: lyrics.isPlaying ? "󰎆" : "󰏤"
        color: lyrics.isPlaying ? root.accentColor : root.widgetColor
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        visible: !barCover.visible
      }
    }

    Item {
      id: textBox
      implicitWidth: Math.min(root.maxLabelWidth, Math.max(50, root.fullW + Style.space(16)))
      implicitHeight: iconGlyph.implicitHeight
      width: implicitWidth
      height: iconGlyph.implicitHeight
      clip: true
      anchors.verticalCenter: parent.verticalCenter

      layer.enabled: root.overflowW > 0
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: maskItem
      }

      // Previous line sliding up and fading out
      Text {
        id: oldText
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 0
        textFormat: Text.PlainText
        text: root.previousText
        color: Qt.darker(root.widgetColor, 1.8)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
        opacity: 0
      }

      // Container for current lyrics text
      Item {
        id: curContainer
        x: {
          if (!root.byWord) return -Math.min(root.scrollX, root.overflowW)
          if (root.overflowW <= 0) return 0
          if (root.clipChars >= root.shown.length) return -root.overflowW
          return -Math.min(Math.max(0, root.typedW + Style.space(8) - Math.max(1, textBox.width)), root.overflowW)
        }
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 0
        height: parent.height
        width: root.fullW + Style.space(24)

        Behavior on x {
          enabled: !glide.running
          NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
        }


        // Settled words revealed so far in bright foreground
        Item {
          id: textClipper
          anchors.verticalCenter: parent.verticalCenter
          height: parent.height
          width: root.byWord ? Math.min(root.fullW, root.settledW) : root.fullW
          clip: root.byWord

          Text {
            id: curFullText
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.shown
            color: root.widgetColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            renderType: Text.NativeRendering
          }
        }

        // Fresh word rising into place (Word-by-word bounce animation on each beat)
        Text {
          id: freshWord
          visible: root.byWord && root.settled < root.typed
          x: root.settledW
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: 0
          textFormat: Text.PlainText
          text: root.shown.slice(root.settled, root.typed)
          color: root.accentColor
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
          opacity: 1
        }
      }

      // Fresh word hop animation (Angel OS beat bounce)
      ParallelAnimation {
        id: freshIn
        NumberAnimation {
          target: freshWord
          property: "opacity"
          from: 0.3
          to: 1.0
          duration: 90
          easing.type: Easing.OutQuad
        }
        NumberAnimation {
          target: freshWord
          property: "anchors.verticalCenterOffset"
          from: 6
          to: 0
          duration: 200
          easing.type: Easing.OutBack
          easing.overshoot: 3
        }
        onFinished: {
          root.settled = root.typed
        }
      }

      // Line slide transition animation (smooth and organic)
      ParallelAnimation {
        id: slide
        NumberAnimation {
          target: oldText
          property: "anchors.verticalCenterOffset"
          from: 0
          to: -8
          duration: 150
          easing.type: Easing.OutQuad
        }
        NumberAnimation {
          target: oldText
          property: "opacity"
          from: 0.8
          to: 0
          duration: 140
          easing.type: Easing.InQuad
        }
        NumberAnimation {
          target: curContainer
          property: "anchors.verticalCenterOffset"
          from: 8
          to: 0
          duration: 190
          easing.type: Easing.OutBack
          easing.overshoot: 1.25
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (mouse.button === Qt.MiddleButton) {
        lyrics.togglePlaying()
      } else if (mouse.button === Qt.RightButton) {
        lyrics.next()
      } else {
        root.popupOpen = !root.popupOpen
      }
    }

    onWheel: function(wheel) {
      if (wheel.modifiers & Qt.ShiftModifier) {
        // Shift + Wheel adjusts lyrics timing offset on the fly (±50ms) and saves per track!
        var delta = wheel.angleDelta.y > 0 ? 50 : -50
        lyrics.setOffset(lyrics.offsetMs + delta)
        root.showOffsetToast = true
        offsetToastTimer.restart()
        return
      }
      if (wheel.angleDelta.y > 0) lyrics.previous()
      else if (wheel.angleDelta.y < 0) lyrics.next()
    }

    onEntered: {
      if (root.bar && lyrics.title) {
        var offsetStr = lyrics.offsetMs !== 0 ? " [" + (lyrics.offsetMs > 0 ? "+" : "") + lyrics.offsetMs + "ms]" : ""
        root.bar.showTooltip(root, lyrics.title + (lyrics.artist ? " — " + lyrics.artist : "") + offsetStr + "\n(Click: Full lyrics | Shift+Wheel: Calibrate sync | Mid: Play/Pause | Right: Next)")
      }
    }
    onExited: {
      if (root.bar) root.bar.hideTooltip(root)
    }
  }

  // Popup card showing full synchronized lyrics
  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(Style.space(480))

    Column {
      anchors.fill: parent
      spacing: Style.space(10)

      // Header with track info & controls
      Row {
        width: parent.width
        spacing: Style.space(12)

        Rectangle {
          width: Style.space(48)
          height: Style.space(48)
          radius: Style.cornerRadius
          color: Qt.rgba(1, 1, 1, 0.05)
          clip: true

          Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            source: lyrics.artUrl
            visible: lyrics.artUrl !== ""
          }

          Text {
            anchors.centerIn: parent
            visible: lyrics.artUrl === ""
            text: "󰎆"
            color: root.accentColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
          }
        }

        Column {
          width: parent.width - Style.space(60) - controlsRow.width
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: lyrics.title || "Nothing playing"
            font.bold: true
            font.pixelSize: Style.font.subtitle
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            color: root.widgetColor
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: lyrics.artist || ""
            font.pixelSize: Style.font.caption
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            color: Qt.darker(root.widgetColor, 1.4)
            elide: Text.ElideRight
            visible: text !== ""
          }

          Text {
            textFormat: Text.PlainText
            text: lyrics.source ? ("via " + lyrics.source) : ""
            font.pixelSize: Style.font.caption - 1
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            color: root.accentColor
            opacity: 0.75
            visible: text !== ""
          }
        }

        Row {
          id: controlsRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          PanelActionButton {
            iconText: "󰒮"
            tooltipText: "Previous track"
            foreground: root.widgetColor
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: lyrics.previous()
          }

          PanelActionButton {
            iconText: lyrics.isPlaying ? "󰏤" : "󰐊"
            tooltipText: lyrics.isPlaying ? "Pause" : "Play"
            foreground: root.widgetColor
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: lyrics.togglePlaying()
          }

          PanelActionButton {
            iconText: "󰒭"
            tooltipText: "Next track"
            foreground: root.widgetColor
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: lyrics.next()
          }
        }
      }

      // Timing calibration bar
      Item {
        width: parent.width
        height: syncText.implicitHeight

        Text {
          id: syncText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Sync: " + (lyrics.offsetMs >= 0 ? "+" : "") + lyrics.offsetMs + " ms"
          font.pixelSize: Style.font.caption
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          color: Qt.darker(root.widgetColor, 1.3)
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          PanelActionButton {
            iconText: "󰍴"
            tooltipText: "-50 ms delay"
            foreground: root.widgetColor
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: lyrics.setOffset(lyrics.offsetMs - 50)
          }

          PanelActionButton {
            iconText: "󰐕"
            tooltipText: "+50 ms advance"
            foreground: root.widgetColor
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: lyrics.setOffset(lyrics.offsetMs + 50)
          }

          PanelActionButton {
            iconText: "󰑐"
            tooltipText: "Reset offset to 0"
            foreground: root.widgetColor
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: lyrics.setOffset(0)
          }
        }
      }

      // Separator line
      Rectangle {
        width: parent.width
        height: Style.spacing.hairline
        color: root.widgetColor
        opacity: 0.15
      }

      // Lyrics list
      Item {
        width: parent.width
        height: parent.height - Style.space(110)

        Text {
          anchors.centerIn: parent
          visible: !lyrics.hasLyrics
          text: lyrics.status === "loading" ? "Fetching lyrics..." : (lyrics.status === "instrumental" ? "♪ Instrumental ♪" : "No synced lyrics found")
          color: Qt.darker(root.widgetColor, 1.5)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        ListView {
          id: lyricsList
          anchors.fill: parent
          visible: lyrics.hasLyrics
          clip: true
          spacing: Style.space(8)
          model: lyrics.lines

          delegate: Rectangle {
            required property var modelData
            required property int index

            readonly property bool isCurrent: index === lyrics.index
            width: lyricsList.width
            height: lineTextItem.implicitHeight + Style.space(8)
            radius: Style.cornerRadius
            color: isCurrent ? Qt.rgba(1, 1, 1, 0.08) : (hoverArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent")

            Text {
              id: lineTextItem
              anchors.centerIn: parent
              width: parent.width - Style.space(16)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: modelData.text || ""
              color: isCurrent
                ? root.accentColor
                : Qt.darker(root.widgetColor, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: isCurrent ? Style.font.subtitle : Style.font.body
              font.bold: isCurrent

              Behavior on color {
                ColorAnimation { duration: 160 }
              }
            }

            MouseArea {
              id: hoverArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (modelData && modelData.t !== undefined) {
                  lyrics.seek(modelData.t)
                }
              }
            }
          }

          Connections {
            target: lyrics
            function onIndexChanged() {
              if (popup.open && lyrics.index >= 0 && lyrics.index < lyrics.lines.length) {
                lyricsList.positionViewAtIndex(lyrics.index, ListView.Center)
              }
            }
          }
        }
      }
    }
  }
}
