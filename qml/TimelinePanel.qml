import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Kadron.Backend

// The editor's bottom panel: the timeline toolbar and the sequence timeline.
// It drives the editor through `app` (Main.qml's window) and asks Main for
// the file dialogs it owns through the signals below.
Rectangle {
    id: panel
    required property var app
    required property MediaPlayer mediaPlayer
    readonly property alias timeline: sequenceTimeline
    signal addClip()
    // The audio track asked for a file at app.audioAddMs.
    signal addMusic()

    color: Theme.panel
    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }
    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 13
        anchors.bottomMargin: 13
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text { text: "Timeline"; color: Theme.text; font.pixelSize: 15; font.weight: Font.DemiBold }
            Text { text: Core.editorProject.hasMedia ? Core.editorProject.clipCount + (Core.editorProject.clipCount === 1 ? " clip · " : " clips · ") + panel.app.timecode(Core.editorProject.sequenceDurationMs) : ""; color: Theme.accent; font.pixelSize: 11 }
            Text { text: Core.editorProject.hasMedia ? "Drag edges to trim, drag clips to reorder, drop audio on the track below, Ctrl + wheel to zoom" : "No clip loaded"; color: Theme.textFaint; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
            EditorButton { iconName: "undo"; subtle: true; enabled: Core.editorProject.canUndo && !Core.exporter.busy; onClicked: Core.editorProject.undo(); ToolTip.visible: hovered; ToolTip.text: "Undo (Ctrl+Z)" }
            EditorButton { iconName: "redo"; subtle: true; enabled: Core.editorProject.canRedo && !Core.exporter.busy; onClicked: Core.editorProject.redo(); ToolTip.visible: hovered; ToolTip.text: "Redo (Ctrl+Shift+Z)" }
            EditorButton { text: "Add clip"; iconName: "plus"; enabled: !Core.exporter.busy; onClicked: panel.addClip() }
            EditorButton {
                objectName: "timelineTextButton"
                text: "Text"
                iconName: "edit"
                enabled: Core.editorProject.hasMedia && !Core.exporter.busy && Core.editorProject.sequenceDurationMs >= 200
                onClicked: panel.app.addTextAt(panel.app.sequencePositionMs)
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "Add text at the playhead and type it on the video"
            }
            EditorButton { text: "Fit"; subtle: true; visible: sequenceTimeline.zoom > 1; onClicked: sequenceTimeline.zoomTo(1, 0) }
            EditorButton { text: "From start"; iconName: "play"; enabled: Core.editorProject.canExport && !Core.exporter.busy; onClicked: panel.app.previewSequence() }
            EditorButton { text: "Split"; iconName: "split"; enabled: Core.editorProject.hasMedia && !Core.exporter.busy && panel.mediaPlayer.position > Core.editorProject.inMs + 100 && panel.mediaPlayer.position < Core.editorProject.outMs - 100; onClicked: Core.editorProject.splitAt(panel.mediaPlayer.position) }
            EditorButton { text: "Mark in"; enabled: Core.editorProject.hasMedia && !Core.exporter.busy; onClicked: Core.editorProject.setInMs(panel.mediaPlayer.position) }
            EditorButton { text: "Mark out"; enabled: Core.editorProject.hasMedia && !Core.exporter.busy; onClicked: Core.editorProject.setOutMs(panel.mediaPlayer.position) }
        }
        Timeline {
            id: sequenceTimeline
            enabled: !Core.exporter.busy
            Layout.fillWidth: true
            Layout.fillHeight: true
            clips: Core.editorProject.clips
            activeIndex: Core.editorProject.activeClipIndex
            playheadMs: panel.app.sequencePositionMs
            playing: panel.app.previewPlaying
            thumbnailSource: Core.thumbnails
            transition: Core.editorProject.transition
            audioItems: Core.editorProject.audioItems
            audioIndex: Core.editorProject.activeAudioIndex
            markers: Core.editorProject.markers
            markerNames: Core.editorProject.markerItems.map(function(item) { return item.name })
            onMarkerRemoveRequested: function(index) { Core.editorProject.removeMarker(index) }
            onMarkerRenameRequested: function(index) { panel.app.renameMarker(index) }
            onAudioSelectRequested: function(index) { Core.editorProject.selectAudio(index) }
            onAudioPlaceRequested: function(index, startMs, inMs, outMs) { Core.editorProject.setAudioPlacement(index, startMs, inMs, outMs) }
            onAudioFadeRequested: function(index, fadeInMs, fadeOutMs) { Core.editorProject.setAudioFades(index, fadeInMs, fadeOutMs) }
            onAudioRemoveRequested: function(index) { Core.editorProject.removeAudio(index) }
            onAudioSplitRequested: function(index, atMs) { Core.editorProject.splitAudio(index, Math.round(atMs)) }
            onAudioAddRequested: function(startMs) {
                panel.app.audioAddMs = startMs
                panel.addMusic()
            }
            onAudioDropped: function(urls, startMs) { panel.app.addAudioFiles(urls, startMs) }
            textItems: Core.editorProject.textItems
            textIndex: Core.editorProject.activeTextIndex
            onTextSelectRequested: function(index) { Core.editorProject.selectText(index) }
            onTextPlaceRequested: function(index, startMs, endMs) { Core.editorProject.setTextPlacement(index, startMs, endMs) }
            onTextRemoveRequested: function(index) { Core.editorProject.removeText(index) }
            onTextSplitRequested: function(index, atMs) { Core.editorProject.splitText(index, Math.round(atMs)) }
            onTextDuplicateRequested: function(index) { Core.editorProject.duplicateText(index) }
            onTextAddRequested: function(startMs) { panel.app.addTextAt(startMs) }
            onTextEditRequested: function(index) { panel.app.typeText(index) }
            onScrubRequested: function(ms) { panel.app.beginScrub(ms) }
            onScrubFinished: panel.app.endScrub()
            onSelectRequested: function(index) {
                panel.app.sequencePlaying = false
                panel.app.sequenceAdvancing = false
                Core.editorProject.selectAudio(-1)
                Core.editorProject.selectText(-1)
                Core.editorProject.selectClip(index)
            }
            onTrimRequested: function(index, inMs, outMs, previewMs) {
                if (Core.editorProject.setClipRange(index, inMs, outMs) && index === Core.editorProject.activeClipIndex)
                    panel.app.requestSourceSeek(previewMs)
            }
            onTrimPreviewRequested: function(index, sourceMs) {
                if (index === Core.editorProject.activeClipIndex) panel.app.requestSourceSeek(sourceMs)
            }
            onTrimPlayRequested: function(index, fromMs, toMs) {
                if (index !== Core.editorProject.activeClipIndex || panel.app.stillActive) return
                panel.app.sequencePlaying = false
                panel.app.sequenceAdvancing = false
                panel.app.trimPlayStopMs = toMs
                panel.app.requestSourceSeek(fromMs)
                panel.mediaPlayer.play()
            }
            onMoveRequested: function(from, to) { Core.editorProject.moveClipTo(from, to) }
            onSplitRequested: Core.editorProject.splitAt(panel.mediaPlayer.position)
            onDuplicateRequested: function(index) { Core.editorProject.duplicateClip(index) }
            onRemoveRequested: function(index) { Core.editorProject.removeClip(index) }
        }
    }
}
