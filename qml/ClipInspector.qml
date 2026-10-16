pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Kadron.Backend

// The editor's right-hand panel for the active clip: trim, speed, volume,
// picture, transitions, the audio track item or text under edit, and export.
// It reads and drives the editor through `app` (Main.qml's window) and asks
// Main for the dialogs it owns through the signals below.
ColumnLayout {
    id: inspector
    required property var app
    required property MediaPlayer mediaPlayer
    // The caption size while its slider is dragged, for the preview; -1 otherwise.
    readonly property real captionDraftSize: captionStyle.draftSize
    signal chooseMusic()
    signal importSubtitles()
    signal exportSubtitles()
    signal replaceSource()
    // Typing in a caption ended with Enter: the timeline takes the keys back.
    signal textDone()

    // Shows the in and out points unless one of their fields is being typed in.
    function syncRangeFields() {
        if (!inField.activeFocus) inField.text = (Core.editorProject.inMs / 1000).toFixed(3)
        if (!outField.activeFocus) outField.text = (Core.editorProject.outMs / 1000).toFixed(3)
    }

    spacing: 10
   // A selected text takes the panel; the clip settings come back
    // when it is let go.
    ColumnLayout {
        visible: inspector.app.activeText === null
        Layout.fillWidth: true
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            spacing: 9
            ColumnLayout {
                Layout.fillWidth: true
                Text { text: "In point · s"; color: Theme.textMuted; font.pixelSize: 11 }
                EditorField {
                    id: inField
                    Layout.fillWidth: true
                    enabled: Core.editorProject.durationMs > 0 && !Core.exporter.busy
                    validator: DoubleValidator { bottom: 0; decimals: 3 }
                    onEditingFinished: Core.editorProject.setInMs(Math.round(Number(text) * 1000))
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Text { text: "Out point · s"; color: Theme.textMuted; font.pixelSize: 11 }
                EditorField {
                    id: outField
                    Layout.fillWidth: true
                    enabled: Core.editorProject.durationMs > 0 && !Core.exporter.busy
                    validator: DoubleValidator { bottom: 0; decimals: 3 }
                    onEditingFinished: Core.editorProject.setOutMs(Math.round(Number(text) * 1000))
                }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.topMargin: 5 }
        RowLayout {
            Layout.fillWidth: true
            Text { text: "Selected duration"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true }
            Text { text: inspector.app.timecode(inspector.app.stillActive ? inspector.app.activeClip.holdMs : (Core.editorProject.outMs - Core.editorProject.inMs) / inspector.app.activeSpeed); color: Theme.accentSoft; font.pixelSize: 17; font.weight: Font.DemiBold }
        }
        EditorButton {
            Layout.fillWidth: true
            text: "Split at playhead  Ctrl+K"
            enabled: Core.editorProject.hasMedia && !Core.exporter.busy && !inspector.app.stillActive && inspector.mediaPlayer.position > Core.editorProject.inMs + 100 && inspector.mediaPlayer.position < Core.editorProject.outMs - 100
            onClicked: Core.editorProject.splitAt(inspector.mediaPlayer.position)
        }

        // Clip volume.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Clip volume"; color: Theme.textMuted; font.pixelSize: 11; Layout.fillWidth: true }
                Text {
                    objectName: "clipVolumeLabel"
                    text: !inspector.app.activeClip ? "" : inspector.app.activeClip.muted ? "Muted" : Math.round((inspector.app.clipVolumeDrag >= 0 ? inspector.app.clipVolumeDrag : inspector.app.activeClip.volume) * 100) + "%"
                    color: inspector.app.activeClip && inspector.app.activeClip.muted ? Theme.warning : Theme.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                EditorButton {
                    objectName: "clipMuteButton"
                    iconName: inspector.app.activeClip && inspector.app.activeClip.muted ? "mute" : "volume"
                    subtle: true
                    enabled: Core.editorProject.hasMedia && !Core.exporter.busy
                    onClicked: Core.editorProject.setClipMuted(Core.editorProject.activeClipIndex, !inspector.app.activeClip.muted)
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: inspector.app.activeClip && inspector.app.activeClip.muted ? "Unmute this clip" : "Mute this clip"
                }
                ToolSlider {
                    objectName: "clipVolumeSlider"
                    Layout.fillWidth: true
                    from: 0
                    to: 2
                    stepSize: 0.05
                    enabled: Core.editorProject.hasMedia && !Core.exporter.busy
                    value: inspector.app.activeClip ? inspector.app.activeClip.volume : 1
                    opacity: inspector.app.activeClip && inspector.app.activeClip.muted ? 0.5 : 1
                    onMoved: {
                        if (pressed) inspector.app.clipVolumeDrag = value
                        else Core.editorProject.setClipVolume(Core.editorProject.activeClipIndex, value)
                    }
                    onPressedChanged: {
                        if (pressed || inspector.app.clipVolumeDrag < 0) return
                        Core.editorProject.setClipVolume(Core.editorProject.activeClipIndex, inspector.app.clipVolumeDrag)
                        inspector.app.clipVolumeDrag = -1
                    }
                }
            }
        }

        // Clip speed.
        ColumnLayout {
            visible: !inspector.app.stillActive
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 4
            Text { text: "Speed"; color: Theme.textMuted; font.pixelSize: 11 }
            SegmentedControl {
                Layout.fillWidth: true
                namePrefix: "clipSpeed"
                options: [0.5, 1, 1.5, 2].map(function(speed) {
                    return { label: speed + "×", value: speed, glyph: speed > 1 ? "bolt" : "", boltSize: speed >= 2 ? 15 : 11 }
                })
                current: inspector.app.activeSpeed
                enabled: Core.editorProject.hasMedia && !Core.exporter.busy
                onActivated: function(speed) { Core.editorProject.setClipSpeed(Core.editorProject.activeClipIndex, speed) }
            }
        }
        EditorButton {
            objectName: "removeSilenceButton"
            Layout.fillWidth: true
            text: Core.editorProject.findingSilence ? "Listening for silence…" : "Remove silence"
            iconName: "audio"
            subtle: true
            enabled: Core.editorProject.hasMedia && !Core.exporter.busy && !Core.editorProject.findingSilence && !(inspector.app.activeClip && inspector.app.activeClip.muted)
            onClicked: Core.editorProject.removeSilence(Core.editorProject.activeClipIndex)
            ToolTip.visible: hovered
            ToolTip.delay: 500
            ToolTip.text: "Cut parts quieter than -35 dB lasting over 0.6 s. Undo brings them back."
        }

        // Picture: freeze frame, turn, crop and colour of this clip.
        ColumnLayout {
            visible: inspector.mediaPlayer.hasVideo
            Layout.fillWidth: true
            spacing: 6
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.bottomMargin: 4 }
            Text { text: "Picture"; color: Theme.textMuted; font.pixelSize: 11 }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                EditorButton {
                    objectName: "freezeFrameButton"
                    Layout.fillWidth: true
                    text: "Freeze frame"
                    iconName: "pause"
                    subtle: true
                    enabled: Core.editorProject.hasMedia && !Core.exporter.busy && !inspector.app.stillActive
                    onClicked: inspector.app.freezeFrame()
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "Hold the frame under the playhead for 2 s"
                }
                EditorButton {
                    objectName: "rotateLeftButton"
                    iconName: "rotateLeft"
                    subtle: true
                    enabled: Core.editorProject.hasMedia && !Core.exporter.busy
                    onClicked: Core.editorProject.setClipRotation(Core.editorProject.activeClipIndex, inspector.app.clipLook.rotation + 270)
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "Turn left"
                }
                EditorButton {
                    objectName: "rotateRightButton"
                    iconName: "rotateRight"
                    subtle: true
                    enabled: Core.editorProject.hasMedia && !Core.exporter.busy
                    onClicked: Core.editorProject.setClipRotation(Core.editorProject.activeClipIndex, inspector.app.clipLook.rotation + 90)
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "Turn right"
                }
                EditorButton {
                    objectName: "cropClipButton"
                    iconName: inspector.app.cropEditing ? "check" : "crop"
                    primary: inspector.app.cropEditing
                    subtle: !inspector.app.cropEditing
                    enabled: Core.editorProject.hasMedia && !Core.exporter.busy
                    onClicked: inspector.app.cropEditing = !inspector.app.cropEditing
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: inspector.app.cropEditing ? "Done cropping" : "Crop: drag the frame on the picture"
                }
            }
            // A held frame's length.
            RowLayout {
                visible: inspector.app.stillActive
                Layout.fillWidth: true
                spacing: 8
                Text { text: "Hold"; color: Theme.textMuted; font.pixelSize: 11; Layout.preferredWidth: 62 }
                ToolSlider {
                    objectName: "holdSlider"
                    Layout.fillWidth: true
                    from: 0.5
                    to: 10
                    stepSize: 0.1
                    enabled: !Core.exporter.busy
                    value: inspector.app.stillActive ? inspector.app.activeClip.holdMs / 1000 : 2
                    onPressedChanged: if (!pressed) Core.editorProject.setClipHold(Core.editorProject.activeClipIndex, Math.round(value * 1000))
                }
                Text { text: (inspector.app.stillActive ? inspector.app.activeClip.holdMs / 1000 : 0).toFixed(1) + " s"; color: Theme.text; font.pixelSize: 12; font.features: { "tnum": 1 }; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight }
            }
            Repeater {
                model: [["brightness", "Brightness"], ["contrast", "Contrast"], ["saturation", "Saturation"]]
                delegate: RowLayout {
                    id: lookRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: lookRow.modelData[1]; color: Theme.textMuted; font.pixelSize: 11; Layout.preferredWidth: 62 }
                    ToolSlider {
                        objectName: "look_" + lookRow.modelData[0]
                        Layout.fillWidth: true
                        from: -1
                        to: 1
                        stepSize: 0.01
                        enabled: Core.editorProject.hasMedia && !Core.exporter.busy
                        value: inspector.app.clipLook[lookRow.modelData[0]]
                        onMoved: {
                            var look = { brightness: inspector.app.clipLook.brightness, contrast: inspector.app.clipLook.contrast, saturation: inspector.app.clipLook.saturation }
                            look[lookRow.modelData[0]] = value
                            if (pressed) inspector.app.lookDrag = look
                            else Core.editorProject.setClipColor(Core.editorProject.activeClipIndex, look.brightness, look.contrast, look.saturation)
                        }
                        onPressedChanged: {
                            if (pressed || !inspector.app.lookDrag) return
                            var look = inspector.app.lookDrag
                            Core.editorProject.setClipColor(Core.editorProject.activeClipIndex, look.brightness, look.contrast, look.saturation)
                            inspector.app.lookDrag = null
                        }
                    }
                    Text {
                        text: (inspector.app.clipLook[lookRow.modelData[0]] > 0 ? "+" : "") + Math.round(inspector.app.clipLook[lookRow.modelData[0]] * 100)
                        color: inspector.app.clipLook[lookRow.modelData[0]] !== 0 ? Theme.text : Theme.textFaint
                        font.pixelSize: 12
                        font.features: { "tnum": 1 }
                        Layout.preferredWidth: 38
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
            EditorButton {
                objectName: "resetPictureButton"
                Layout.fillWidth: true
                visible: inspector.app.lookActive && !inspector.app.cropEditing
                text: "Reset picture"
                subtle: true
                enabled: !Core.exporter.busy
                onClicked: {
                    var index = Core.editorProject.activeClipIndex
                    Core.editorProject.setClipRotation(index, 0)
                    Core.editorProject.setClipCrop(index, 0, 0, 1, 1)
                    Core.editorProject.setClipColor(index, 0, 0, 0)
                    inspector.app.cropRevision++
                }
            }
        }

        // How clips meet.
        ColumnLayout {
            visible: Core.editorProject.clipCount > 1
            Layout.fillWidth: true
            spacing: 6
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.bottomMargin: 4 }
            Text { text: "Between clips"; color: Theme.textMuted; font.pixelSize: 11 }
            ToolCombo {
                objectName: "transitionCombo"
                Layout.fillWidth: true
                enabled: !Core.exporter.busy
                textRole: "label"
                valueRole: "value"
                model: [{ value: "cut", label: "Cut" }, { value: "fade", label: "Fade through black" }, { value: "crossfade", label: "Crossfade" }]
                currentIndex: ["cut", "fade", "crossfade"].indexOf(Core.editorProject.transition)
                onActivated: Core.editorProject.setTransition(currentValue)
            }
            RowLayout {
                visible: Core.editorProject.transition !== "cut"
                Layout.fillWidth: true
                spacing: 8
                ToolSlider {
                    objectName: "transitionSlider"
                    Layout.fillWidth: true
                    from: 200
                    to: 2000
                    stepSize: 100
                    enabled: !Core.exporter.busy
                    value: Core.editorProject.transitionMs
                    onMoved: {
                        if (pressed) inspector.app.transitionDrag = value
                        else Core.editorProject.setTransitionMs(value)
                    }
                    onPressedChanged: {
                        if (pressed || inspector.app.transitionDrag < 0) return
                        Core.editorProject.setTransitionMs(inspector.app.transitionDrag)
                        inspector.app.transitionDrag = -1
                    }
                }
                Text {
                    text: ((inspector.app.transitionDrag >= 0 ? inspector.app.transitionDrag : Core.editorProject.transitionMs) / 1000).toFixed(1) + " s"
                    color: Theme.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    Layout.preferredWidth: 34
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        // Audio track: music and sounds placed on the sequence.
        ColumnLayout {
            visible: Core.editorProject.hasMedia
            Layout.fillWidth: true
            spacing: 6
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.bottomMargin: 4 }
            Text { text: "Audio track"; color: Theme.textMuted; font.pixelSize: 11 }
            EditorButton {
                objectName: "addMusicButton"
                Layout.fillWidth: true
                text: "Add audio at playhead…"
                iconName: "music"
                enabled: !Core.exporter.busy
                onClicked: {
                    inspector.app.audioAddMs = inspector.app.sequencePositionMs
                    inspector.chooseMusic()
                }
            }
            RowLayout {
                visible: inspector.app.activeAudio !== null
                Layout.fillWidth: true
                spacing: 4
                ToolIcon { name: "music"; tint: Theme.accent; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                Text {
                    objectName: "musicName"
                    text: inspector.app.activeAudio ? inspector.app.activeAudio.name : ""
                    color: Theme.text
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                }
                EditorButton {
                    objectName: "removeMusicButton"
                    iconName: "close"
                    subtle: true
                    enabled: !Core.exporter.busy
                    onClicked: Core.editorProject.removeAudio(Core.editorProject.activeAudioIndex)
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "Remove from the audio track (Delete)"
                }
            }
            Text {
                visible: inspector.app.activeAudio !== null
                text: inspector.app.activeAudio ? "From " + inspector.app.timecode(inspector.app.activeAudio.startMs) + " for " + inspector.app.timecode(inspector.app.activeAudio.lengthMs) : ""
                color: Theme.textFaint
                font.pixelSize: 11
                // Fill and wrap, so the text never widens the panel.
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            RowLayout {
                visible: inspector.app.activeAudio !== null
                Layout.fillWidth: true
                spacing: 8
                ToolSlider {
                    objectName: "musicVolumeSlider"
                    Layout.fillWidth: true
                    from: 0
                    to: 2
                    stepSize: 0.05
                    enabled: !Core.exporter.busy
                    value: inspector.app.activeAudio ? inspector.app.activeAudio.volume : 0.5
                    onMoved: {
                        if (pressed) inspector.app.audioVolumeDrag = value
                        else Core.editorProject.setAudioVolume(Core.editorProject.activeAudioIndex, value)
                    }
                    onPressedChanged: {
                        if (pressed || inspector.app.audioVolumeDrag < 0) return
                        Core.editorProject.setAudioVolume(Core.editorProject.activeAudioIndex, inspector.app.audioVolumeDrag)
                        inspector.app.audioVolumeDrag = -1
                    }
                }
                Text {
                    text: inspector.app.activeAudio ? Math.round((inspector.app.audioVolumeDrag >= 0 ? inspector.app.audioVolumeDrag : inspector.app.activeAudio.volume) * 100) + "%" : ""
                    color: Theme.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    Layout.preferredWidth: 34
                    horizontalAlignment: Text.AlignRight
                }
            }
            Text {
                visible: inspector.app.activeAudio !== null
                text: inspector.app.activeAudio ? "Fade in " + (inspector.app.activeAudio.fadeInMs / 1000).toFixed(1) + " s · fade out " + (inspector.app.activeAudio.fadeOutMs / 1000).toFixed(1) + " s"
                                         + (inspector.app.activeAudio.fadeInMs + inspector.app.activeAudio.fadeOutMs === 0 ? " · drag the dots at the top corners" : "") : ""
                color: Theme.textFaint
                font.pixelSize: 11
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            ToolCheck {
                objectName: "musicDuckCheck"
                visible: Core.editorProject.audioCount > 0
                text: "Quieter while someone speaks"
                enabled: !Core.exporter.busy
                checked: Core.editorProject.musicDuck
                onToggled: Core.editorProject.setMusicDuck(checked)
            }
            Text {
                Layout.fillWidth: true
                text: Core.editorProject.audioCount === 0
                      ? "Drop music or sounds on the audio track under the clips, or add them here."
                      : "Drag items on the audio track to move them and their edges to trim. Sound past the end of the video fades out."
                wrapMode: Text.WordWrap
                color: Theme.textFaint
                font.pixelSize: 10
            }
        }
    }

    // Text track: captions drawn over the video.
    ColumnLayout {
        visible: Core.editorProject.hasMedia
        Layout.fillWidth: true
        spacing: 6
        Rectangle { visible: inspector.app.activeText === null; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.bottomMargin: 4 }
        Text { text: "Text on video"; color: Theme.textMuted; font.pixelSize: 11 }
        EditorButton {
            objectName: "addTextButton"
            visible: inspector.app.activeText === null
            Layout.fillWidth: true
            text: "Add text at playhead"
            iconName: "plus"
            enabled: !Core.exporter.busy && Core.editorProject.sequenceDurationMs >= 200
            onClicked: inspector.app.addTextAt(inspector.app.sequencePositionMs)
        }
        RowLayout {
            visible: inspector.app.activeText === null
            Layout.fillWidth: true
            spacing: 6
            EditorButton {
                objectName: "importSubtitlesButton"
                Layout.fillWidth: true
                text: "Import SRT…"
                iconName: "file"
                subtle: true
                enabled: !Core.exporter.busy
                onClicked: inspector.importSubtitles()
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "Add captions from an SRT or VTT file to the text track"
            }
            EditorButton {
                objectName: "exportSubtitlesButton"
                Layout.fillWidth: true
                text: "Save SRT…"
                iconName: "save"
                subtle: true
                enabled: Core.editorProject.textItems.length > 0
                onClicked: inspector.exportSubtitles()
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "Save the text track as subtitles for YouTube or a player"
            }
        }
        TextArea {
            id: captionField
            objectName: "captionField"
            visible: inspector.app.activeText !== null
            Layout.fillWidth: true
            enabled: !Core.exporter.busy
            wrapMode: TextEdit.Wrap
            color: Theme.text
            selectionColor: Theme.accent
            selectedTextColor: Theme.accentInk
            font.family: Theme.fontFamily
            font.pixelSize: 12
            padding: 9
            background: Rectangle {
                radius: 8
                color: Theme.field
                border.width: captionField.activeFocus ? 2 : 1
                border.color: captionField.activeFocus ? Theme.accent : Theme.lineStrong
            }
            // Follows the selected caption until the user types.
            readonly property string savedText: inspector.app.activeText ? inspector.app.activeText.text : ""
            onSavedTextChanged: if (text !== savedText) text = savedText
            Component.onCompleted: text = savedText
            // Typed characters go into the text, not to the J/K/L/Space shortcuts.
            Keys.onShortcutOverride: function(event) {
                event.accepted = event.text.length > 0 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))
            }
            // Enter keeps the text, Shift+Enter starts a new line.
            Keys.onPressed: function(event) {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                    event.accepted = true
                    editingFinished()
                    inspector.textDone()
                }
            }
            onEditingFinished: {
                if (!inspector.app.activeText) return
                if (!Core.editorProject.setTextContent(Core.editorProject.activeTextIndex, text)) text = savedText
            }
        }
        TextStyleEditor {
            id: captionStyle
            visible: inspector.app.activeText !== null
            Layout.fillWidth: true
            enabled: !Core.exporter.busy
            item: inspector.app.activeText
            onChangeRequested: function(changes) { Core.editorProject.setTextStyle(Core.editorProject.activeTextIndex, changes) }
        }
        RowLayout {
            visible: inspector.app.activeText !== null
            Layout.fillWidth: true
            spacing: 6
            EditorButton {
                objectName: "removeTextButton"
                Layout.fillWidth: true
                text: "Remove text"
                iconName: "close"
                subtle: true
                enabled: !Core.exporter.busy
                onClicked: Core.editorProject.removeText(Core.editorProject.activeTextIndex)
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "Remove the text (Delete on the timeline)"
            }
            EditorButton {
                objectName: "doneTextButton"
                Layout.fillWidth: true
                text: "Done"
                onClicked: Core.editorProject.selectText(-1)
            }
        }
        Text {
            Layout.fillWidth: true
            text: inspector.app.activeText
                  ? "Shown from " + inspector.app.timecode(inspector.app.activeText.startMs) + " for " + inspector.app.timecode(inspector.app.activeText.lengthMs) + ". Drag it on the picture to place it, on the text track to retime it."
                  : Core.editorProject.textItems.length === 0
                    ? "Titles and captions, burnt into the export. Double-click the text track to add one."
                    : "Click a caption on the text track to edit it."
            wrapMode: Text.WordWrap
            color: Theme.textFaint
            font.pixelSize: 10
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Text { text: "Sequence duration"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true }
        Text { text: inspector.app.timecode(Core.editorProject.sequenceDurationMs); color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold }
    }
    EditorButton {
        objectName: "copyChaptersButton"
        Layout.fillWidth: true
        visible: Core.editorProject.markers.length > 0
        text: "Copy chapters"
        iconName: "copy"
        subtle: true
        onClicked: inspector.app.copyChapters()
        ToolTip.visible: hovered
        ToolTip.delay: 500
        ToolTip.text: "Markers as a YouTube chapter list. Double-click a marker to name it."
    }
    RowLayout {
        Layout.fillWidth: true
        visible: Core.exporter.available
        spacing: 8
        Text { text: "Encoder"; color: Theme.textMuted; font.pixelSize: 12 }
        ToolCombo {
            id: encoderCombo
            objectName: "encoderCombo"
            Layout.fillWidth: true
            enabled: !Core.exporter.busy
            textRole: "label"
            valueRole: "value"
            model: encoderItems
            readonly property var encoderItems: {
                var names = { nvenc: "NVIDIA NVENC (GPU)", qsv: "Intel Quick Sync (GPU)", amf: "AMD AMF (GPU)" }
                var items = [{ value: "auto", label: !Core.exporter.encodersChecked ? "Auto (checking GPU…)"
                                                    : Core.exporter.hardwareEncoders.length > 0 ? "Auto · " + names[Core.exporter.hardwareEncoders[0]]
                                                    : "Auto · CPU (no GPU encoder)" },
                             { value: "cpu", label: "CPU (x264)" }]
                for (var i = 0; i < Core.exporter.hardwareEncoders.length; i++)
                    items.push({ value: Core.exporter.hardwareEncoders[i], label: names[Core.exporter.hardwareEncoders[i]] })
                return items
            }
            currentIndex: {
                for (var i = 0; i < encoderItems.length; i++)
                    if (encoderItems[i].value === Core.exporter.encoder) return i
                return 0
            }
            onActivated: Core.exporter.encoder = currentValue
        }
    }
    Text {
        Layout.fillWidth: true
        visible: !Core.exporter.available
        text: "FFmpeg is required for export. Set KADRON_FFMPEG or add it to PATH."
        wrapMode: Text.WordWrap
        color: Theme.warning
        font.pixelSize: 11
    }
    Text {
        Layout.fillWidth: true
        visible: Core.exporter.errorText.length > 0
        text: Core.exporter.errorText
        wrapMode: Text.WordWrap
        color: Theme.danger
        font.pixelSize: 11
    }
    Text {
        Layout.fillWidth: true
        visible: Core.exporter.busy
        text: Core.exporter.stage + "  " + Core.exporter.progress + "%  ·  " + Core.exporter.encoderUsed
        color: Theme.textSoft
        font.pixelSize: 11
    }
    StudioProgress {
        visible: Core.exporter.busy
        Layout.fillWidth: true
        value: Core.exporter.progress / 100
    }
    Text {
        Layout.fillWidth: true
        visible: Core.exporter.busy && inspector.app.exportQueue.length > 0
        text: inspector.app.exportQueue.length + (inspector.app.exportQueue.length === 1 ? " more export waits" : " more exports wait") + " in the queue"
        color: Theme.textFaint
        font.pixelSize: 11
    }
    EditorButton {
        Layout.fillWidth: true
        visible: Core.exporter.busy
        text: inspector.app.exportQueue.length > 0 ? "Cancel export and queue" : "Cancel export"
        danger: true
        onClicked: inspector.app.cancelExport()
    }
    RowLayout {
        id: exportResultRow
        Layout.fillWidth: true
        spacing: 6
        visible: Core.exporter.outputUrl.toString().length > 0 && !Core.exporter.busy
        ResultEntrance { target: exportResultRow; file: Core.exporter.busy ? "" : Core.exporter.outputUrl }
        EditorButton {
            Layout.fillWidth: true
            text: "Open exported file"
            onClicked: Qt.openUrlExternally(Core.exporter.outputUrl)
        }
        EditorButton {
            iconName: "folder"
            implicitWidth: 38
            ToolTip.visible: hovered
            ToolTip.delay: 500
            ToolTip.text: "Show in folder"
            onClicked: Core.shellIntegration.reveal(Core.exporter.outputUrl)
        }
        CopyButton { compact: true; file: Core.exporter.outputUrl }
    }
    EditorButton {
        objectName: "replaceSourceButton"
        Layout.fillWidth: true
        visible: inspector.app.canReplaceSource && exportResultRow.visible
        text: "Replace original…"
        iconName: "file"
        subtle: true
        onClicked: inspector.replaceSource()
        ToolTip.visible: hovered
        ToolTip.delay: 500
        ToolTip.text: "Move " + decodeURIComponent(inspector.app.exportSourceUrl.toString().replace(/^.*\//, "")) + " to the Recycle Bin and give the export its name"
    }
}
