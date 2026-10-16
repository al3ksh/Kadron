import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

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
        if (!inField.activeFocus) inField.text = (editorProject.inMs / 1000).toFixed(3)
        if (!outField.activeFocus) outField.text = (editorProject.outMs / 1000).toFixed(3)
    }

    spacing: 10
   // A selected text takes the panel; the clip settings come back
    // when it is let go.
    ColumnLayout {
        visible: app.activeText === null
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
                    enabled: editorProject.durationMs > 0 && !exporter.busy
                    validator: DoubleValidator { bottom: 0; decimals: 3 }
                    onEditingFinished: editorProject.setInMs(Math.round(Number(text) * 1000))
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Text { text: "Out point · s"; color: Theme.textMuted; font.pixelSize: 11 }
                EditorField {
                    id: outField
                    Layout.fillWidth: true
                    enabled: editorProject.durationMs > 0 && !exporter.busy
                    validator: DoubleValidator { bottom: 0; decimals: 3 }
                    onEditingFinished: editorProject.setOutMs(Math.round(Number(text) * 1000))
                }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.topMargin: 5 }
        RowLayout {
            Layout.fillWidth: true
            Text { text: "Selected duration"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true }
            Text { text: app.timecode(app.stillActive ? app.activeClip.holdMs : (editorProject.outMs - editorProject.inMs) / app.activeSpeed); color: Theme.accentSoft; font.pixelSize: 17; font.weight: Font.DemiBold }
        }
        EditorButton {
            Layout.fillWidth: true
            text: "Split at playhead  Ctrl+K"
            enabled: editorProject.hasMedia && !exporter.busy && !app.stillActive && mediaPlayer.position > editorProject.inMs + 100 && mediaPlayer.position < editorProject.outMs - 100
            onClicked: editorProject.splitAt(mediaPlayer.position)
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
                    text: !app.activeClip ? "" : app.activeClip.muted ? "Muted" : Math.round((app.clipVolumeDrag >= 0 ? app.clipVolumeDrag : app.activeClip.volume) * 100) + "%"
                    color: app.activeClip && app.activeClip.muted ? Theme.warning : Theme.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                EditorButton {
                    objectName: "clipMuteButton"
                    iconName: app.activeClip && app.activeClip.muted ? "mute" : "volume"
                    subtle: true
                    enabled: editorProject.hasMedia && !exporter.busy
                    onClicked: editorProject.setClipMuted(editorProject.activeClipIndex, !app.activeClip.muted)
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: app.activeClip && app.activeClip.muted ? "Unmute this clip" : "Mute this clip"
                }
                ToolSlider {
                    objectName: "clipVolumeSlider"
                    Layout.fillWidth: true
                    from: 0
                    to: 2
                    stepSize: 0.05
                    enabled: editorProject.hasMedia && !exporter.busy
                    value: app.activeClip ? app.activeClip.volume : 1
                    opacity: app.activeClip && app.activeClip.muted ? 0.5 : 1
                    onMoved: {
                        if (pressed) app.clipVolumeDrag = value
                        else editorProject.setClipVolume(editorProject.activeClipIndex, value)
                    }
                    onPressedChanged: {
                        if (pressed || app.clipVolumeDrag < 0) return
                        editorProject.setClipVolume(editorProject.activeClipIndex, app.clipVolumeDrag)
                        app.clipVolumeDrag = -1
                    }
                }
            }
        }

        // Clip speed.
        ColumnLayout {
            visible: !app.stillActive
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
                current: app.activeSpeed
                enabled: editorProject.hasMedia && !exporter.busy
                onActivated: function(speed) { editorProject.setClipSpeed(editorProject.activeClipIndex, speed) }
            }
        }
        EditorButton {
            objectName: "removeSilenceButton"
            Layout.fillWidth: true
            text: editorProject.findingSilence ? "Listening for silence…" : "Remove silence"
            iconName: "audio"
            subtle: true
            enabled: editorProject.hasMedia && !exporter.busy && !editorProject.findingSilence && !(app.activeClip && app.activeClip.muted)
            onClicked: editorProject.removeSilence(editorProject.activeClipIndex)
            ToolTip.visible: hovered
            ToolTip.delay: 500
            ToolTip.text: "Cut parts quieter than -35 dB lasting over 0.6 s. Undo brings them back."
        }

        // Picture: freeze frame, turn, crop and colour of this clip.
        ColumnLayout {
            visible: mediaPlayer.hasVideo
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
                    enabled: editorProject.hasMedia && !exporter.busy && !app.stillActive
                    onClicked: app.freezeFrame()
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "Hold the frame under the playhead for 2 s"
                }
                EditorButton {
                    objectName: "rotateLeftButton"
                    iconName: "rotateLeft"
                    subtle: true
                    enabled: editorProject.hasMedia && !exporter.busy
                    onClicked: editorProject.setClipRotation(editorProject.activeClipIndex, app.clipLook.rotation + 270)
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "Turn left"
                }
                EditorButton {
                    objectName: "rotateRightButton"
                    iconName: "rotateRight"
                    subtle: true
                    enabled: editorProject.hasMedia && !exporter.busy
                    onClicked: editorProject.setClipRotation(editorProject.activeClipIndex, app.clipLook.rotation + 90)
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "Turn right"
                }
                EditorButton {
                    objectName: "cropClipButton"
                    iconName: app.cropEditing ? "check" : "crop"
                    primary: app.cropEditing
                    subtle: !app.cropEditing
                    enabled: editorProject.hasMedia && !exporter.busy
                    onClicked: app.cropEditing = !app.cropEditing
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: app.cropEditing ? "Done cropping" : "Crop: drag the frame on the picture"
                }
            }
            // A held frame's length.
            RowLayout {
                visible: app.stillActive
                Layout.fillWidth: true
                spacing: 8
                Text { text: "Hold"; color: Theme.textMuted; font.pixelSize: 11; Layout.preferredWidth: 62 }
                ToolSlider {
                    objectName: "holdSlider"
                    Layout.fillWidth: true
                    from: 0.5
                    to: 10
                    stepSize: 0.1
                    enabled: !exporter.busy
                    value: app.stillActive ? app.activeClip.holdMs / 1000 : 2
                    onPressedChanged: if (!pressed) editorProject.setClipHold(editorProject.activeClipIndex, Math.round(value * 1000))
                }
                Text { text: (app.stillActive ? app.activeClip.holdMs / 1000 : 0).toFixed(1) + " s"; color: Theme.text; font.pixelSize: 12; font.features: { "tnum": 1 }; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight }
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
                        enabled: editorProject.hasMedia && !exporter.busy
                        value: app.clipLook[lookRow.modelData[0]]
                        onMoved: {
                            var look = { brightness: app.clipLook.brightness, contrast: app.clipLook.contrast, saturation: app.clipLook.saturation }
                            look[lookRow.modelData[0]] = value
                            if (pressed) app.lookDrag = look
                            else editorProject.setClipColor(editorProject.activeClipIndex, look.brightness, look.contrast, look.saturation)
                        }
                        onPressedChanged: {
                            if (pressed || !app.lookDrag) return
                            var look = app.lookDrag
                            editorProject.setClipColor(editorProject.activeClipIndex, look.brightness, look.contrast, look.saturation)
                            app.lookDrag = null
                        }
                    }
                    Text {
                        text: (app.clipLook[lookRow.modelData[0]] > 0 ? "+" : "") + Math.round(app.clipLook[lookRow.modelData[0]] * 100)
                        color: app.clipLook[lookRow.modelData[0]] !== 0 ? Theme.text : Theme.textFaint
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
                visible: app.lookActive && !app.cropEditing
                text: "Reset picture"
                subtle: true
                enabled: !exporter.busy
                onClicked: {
                    var index = editorProject.activeClipIndex
                    editorProject.setClipRotation(index, 0)
                    editorProject.setClipCrop(index, 0, 0, 1, 1)
                    editorProject.setClipColor(index, 0, 0, 0)
                    app.cropRevision++
                }
            }
        }

        // How clips meet.
        ColumnLayout {
            visible: editorProject.clipCount > 1
            Layout.fillWidth: true
            spacing: 6
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.bottomMargin: 4 }
            Text { text: "Between clips"; color: Theme.textMuted; font.pixelSize: 11 }
            ToolCombo {
                objectName: "transitionCombo"
                Layout.fillWidth: true
                enabled: !exporter.busy
                textRole: "label"
                valueRole: "value"
                model: [{ value: "cut", label: "Cut" }, { value: "fade", label: "Fade through black" }, { value: "crossfade", label: "Crossfade" }]
                currentIndex: ["cut", "fade", "crossfade"].indexOf(editorProject.transition)
                onActivated: editorProject.setTransition(currentValue)
            }
            RowLayout {
                visible: editorProject.transition !== "cut"
                Layout.fillWidth: true
                spacing: 8
                ToolSlider {
                    objectName: "transitionSlider"
                    Layout.fillWidth: true
                    from: 200
                    to: 2000
                    stepSize: 100
                    enabled: !exporter.busy
                    value: editorProject.transitionMs
                    onMoved: {
                        if (pressed) app.transitionDrag = value
                        else editorProject.setTransitionMs(value)
                    }
                    onPressedChanged: {
                        if (pressed || app.transitionDrag < 0) return
                        editorProject.setTransitionMs(app.transitionDrag)
                        app.transitionDrag = -1
                    }
                }
                Text {
                    text: ((app.transitionDrag >= 0 ? app.transitionDrag : editorProject.transitionMs) / 1000).toFixed(1) + " s"
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
            visible: editorProject.hasMedia
            Layout.fillWidth: true
            spacing: 6
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.bottomMargin: 4 }
            Text { text: "Audio track"; color: Theme.textMuted; font.pixelSize: 11 }
            EditorButton {
                objectName: "addMusicButton"
                Layout.fillWidth: true
                text: "Add audio at playhead…"
                iconName: "music"
                enabled: !exporter.busy
                onClicked: {
                    app.audioAddMs = app.sequencePositionMs
                    inspector.chooseMusic()
                }
            }
            RowLayout {
                visible: app.activeAudio !== null
                Layout.fillWidth: true
                spacing: 4
                ToolIcon { name: "music"; tint: Theme.accent; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                Text {
                    objectName: "musicName"
                    text: app.activeAudio ? app.activeAudio.name : ""
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
                    enabled: !exporter.busy
                    onClicked: editorProject.removeAudio(editorProject.activeAudioIndex)
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "Remove from the audio track (Delete)"
                }
            }
            Text {
                visible: app.activeAudio !== null
                text: app.activeAudio ? "From " + app.timecode(app.activeAudio.startMs) + " for " + app.timecode(app.activeAudio.lengthMs) : ""
                color: Theme.textFaint
                font.pixelSize: 11
                // Fill and wrap, so the text never widens the panel.
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            RowLayout {
                visible: app.activeAudio !== null
                Layout.fillWidth: true
                spacing: 8
                ToolSlider {
                    objectName: "musicVolumeSlider"
                    Layout.fillWidth: true
                    from: 0
                    to: 2
                    stepSize: 0.05
                    enabled: !exporter.busy
                    value: app.activeAudio ? app.activeAudio.volume : 0.5
                    onMoved: {
                        if (pressed) app.audioVolumeDrag = value
                        else editorProject.setAudioVolume(editorProject.activeAudioIndex, value)
                    }
                    onPressedChanged: {
                        if (pressed || app.audioVolumeDrag < 0) return
                        editorProject.setAudioVolume(editorProject.activeAudioIndex, app.audioVolumeDrag)
                        app.audioVolumeDrag = -1
                    }
                }
                Text {
                    text: app.activeAudio ? Math.round((app.audioVolumeDrag >= 0 ? app.audioVolumeDrag : app.activeAudio.volume) * 100) + "%" : ""
                    color: Theme.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    Layout.preferredWidth: 34
                    horizontalAlignment: Text.AlignRight
                }
            }
            Text {
                visible: app.activeAudio !== null
                text: app.activeAudio ? "Fade in " + (app.activeAudio.fadeInMs / 1000).toFixed(1) + " s · fade out " + (app.activeAudio.fadeOutMs / 1000).toFixed(1) + " s"
                                         + (app.activeAudio.fadeInMs + app.activeAudio.fadeOutMs === 0 ? " · drag the dots at the top corners" : "") : ""
                color: Theme.textFaint
                font.pixelSize: 11
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            ToolCheck {
                objectName: "musicDuckCheck"
                visible: editorProject.audioCount > 0
                text: "Quieter while someone speaks"
                enabled: !exporter.busy
                checked: editorProject.musicDuck
                onToggled: editorProject.setMusicDuck(checked)
            }
            Text {
                Layout.fillWidth: true
                text: editorProject.audioCount === 0
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
        visible: editorProject.hasMedia
        Layout.fillWidth: true
        spacing: 6
        Rectangle { visible: app.activeText === null; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.bottomMargin: 4 }
        Text { text: "Text on video"; color: Theme.textMuted; font.pixelSize: 11 }
        EditorButton {
            objectName: "addTextButton"
            visible: app.activeText === null
            Layout.fillWidth: true
            text: "Add text at playhead"
            iconName: "plus"
            enabled: !exporter.busy && editorProject.sequenceDurationMs >= 200
            onClicked: app.addTextAt(app.sequencePositionMs)
        }
        RowLayout {
            visible: app.activeText === null
            Layout.fillWidth: true
            spacing: 6
            EditorButton {
                objectName: "importSubtitlesButton"
                Layout.fillWidth: true
                text: "Import SRT…"
                iconName: "file"
                subtle: true
                enabled: !exporter.busy
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
                enabled: editorProject.textItems.length > 0
                onClicked: inspector.exportSubtitles()
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "Save the text track as subtitles for YouTube or a player"
            }
        }
        TextArea {
            id: captionField
            objectName: "captionField"
            visible: app.activeText !== null
            Layout.fillWidth: true
            enabled: !exporter.busy
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
            readonly property string savedText: app.activeText ? app.activeText.text : ""
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
                if (!app.activeText) return
                if (!editorProject.setTextContent(editorProject.activeTextIndex, text)) text = savedText
            }
        }
        TextStyleEditor {
            id: captionStyle
            visible: app.activeText !== null
            Layout.fillWidth: true
            enabled: !exporter.busy
            item: app.activeText
            onChangeRequested: function(changes) { editorProject.setTextStyle(editorProject.activeTextIndex, changes) }
        }
        RowLayout {
            visible: app.activeText !== null
            Layout.fillWidth: true
            spacing: 6
            EditorButton {
                objectName: "removeTextButton"
                Layout.fillWidth: true
                text: "Remove text"
                iconName: "close"
                subtle: true
                enabled: !exporter.busy
                onClicked: editorProject.removeText(editorProject.activeTextIndex)
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "Remove the text (Delete on the timeline)"
            }
            EditorButton {
                objectName: "doneTextButton"
                Layout.fillWidth: true
                text: "Done"
                onClicked: editorProject.selectText(-1)
            }
        }
        Text {
            Layout.fillWidth: true
            text: app.activeText
                  ? "Shown from " + app.timecode(app.activeText.startMs) + " for " + app.timecode(app.activeText.lengthMs) + ". Drag it on the picture to place it, on the text track to retime it."
                  : editorProject.textItems.length === 0
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
        Text { text: app.timecode(editorProject.sequenceDurationMs); color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold }
    }
    EditorButton {
        objectName: "copyChaptersButton"
        Layout.fillWidth: true
        visible: editorProject.markers.length > 0
        text: "Copy chapters"
        iconName: "copy"
        subtle: true
        onClicked: app.copyChapters()
        ToolTip.visible: hovered
        ToolTip.delay: 500
        ToolTip.text: "Markers as a YouTube chapter list. Double-click a marker to name it."
    }
    RowLayout {
        Layout.fillWidth: true
        visible: exporter.available
        spacing: 8
        Text { text: "Encoder"; color: Theme.textMuted; font.pixelSize: 12 }
        ToolCombo {
            id: encoderCombo
            objectName: "encoderCombo"
            Layout.fillWidth: true
            enabled: !exporter.busy
            textRole: "label"
            valueRole: "value"
            model: encoderItems
            readonly property var encoderItems: {
                var names = { nvenc: "NVIDIA NVENC (GPU)", qsv: "Intel Quick Sync (GPU)", amf: "AMD AMF (GPU)" }
                var items = [{ value: "auto", label: !exporter.encodersChecked ? "Auto (checking GPU…)"
                                                    : exporter.hardwareEncoders.length > 0 ? "Auto · " + names[exporter.hardwareEncoders[0]]
                                                    : "Auto · CPU (no GPU encoder)" },
                             { value: "cpu", label: "CPU (x264)" }]
                for (var i = 0; i < exporter.hardwareEncoders.length; i++)
                    items.push({ value: exporter.hardwareEncoders[i], label: names[exporter.hardwareEncoders[i]] })
                return items
            }
            currentIndex: {
                for (var i = 0; i < encoderItems.length; i++)
                    if (encoderItems[i].value === exporter.encoder) return i
                return 0
            }
            onActivated: exporter.encoder = currentValue
        }
    }
    Text {
        Layout.fillWidth: true
        visible: !exporter.available
        text: "FFmpeg is required for export. Set KADRON_FFMPEG or add it to PATH."
        wrapMode: Text.WordWrap
        color: Theme.warning
        font.pixelSize: 11
    }
    Text {
        Layout.fillWidth: true
        visible: exporter.errorText.length > 0
        text: exporter.errorText
        wrapMode: Text.WordWrap
        color: Theme.danger
        font.pixelSize: 11
    }
    Text {
        Layout.fillWidth: true
        visible: exporter.busy
        text: exporter.stage + "  " + exporter.progress + "%  ·  " + exporter.encoderUsed
        color: Theme.textSoft
        font.pixelSize: 11
    }
    StudioProgress {
        visible: exporter.busy
        Layout.fillWidth: true
        value: exporter.progress / 100
    }
    Text {
        Layout.fillWidth: true
        visible: exporter.busy && app.exportQueue.length > 0
        text: app.exportQueue.length + (app.exportQueue.length === 1 ? " more export waits" : " more exports wait") + " in the queue"
        color: Theme.textFaint
        font.pixelSize: 11
    }
    EditorButton {
        Layout.fillWidth: true
        visible: exporter.busy
        text: app.exportQueue.length > 0 ? "Cancel export and queue" : "Cancel export"
        danger: true
        onClicked: app.cancelExport()
    }
    RowLayout {
        id: exportResultRow
        Layout.fillWidth: true
        spacing: 6
        visible: exporter.outputUrl.toString().length > 0 && !exporter.busy
        ResultEntrance { target: exportResultRow; file: exporter.busy ? "" : exporter.outputUrl }
        EditorButton {
            Layout.fillWidth: true
            text: "Open exported file"
            onClicked: Qt.openUrlExternally(exporter.outputUrl)
        }
        EditorButton {
            iconName: "folder"
            implicitWidth: 38
            ToolTip.visible: hovered
            ToolTip.delay: 500
            ToolTip.text: "Show in folder"
            onClicked: shellIntegration.reveal(exporter.outputUrl)
        }
        CopyButton { compact: true; file: exporter.outputUrl }
    }
    EditorButton {
        objectName: "replaceSourceButton"
        Layout.fillWidth: true
        visible: app.canReplaceSource && exportResultRow.visible
        text: "Replace original…"
        iconName: "file"
        subtle: true
        onClicked: inspector.replaceSource()
        ToolTip.visible: hovered
        ToolTip.delay: 500
        ToolTip.text: "Move " + decodeURIComponent(app.exportSourceUrl.toString().replace(/^.*\//, "")) + " to the Recycle Bin and give the export its name"
    }
}
