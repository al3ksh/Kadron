# Kadron Interface

## Direction

A focused post-production desk, not a dashboard. The footage and the current task lead; navigation and status stay calm. Controls react quickly without making users wait for decorative motion.

## Identity

- The Kadron mark is a white frame bracket (a *kadr*) cut by a lime chevron, so it reads as a K. The vector source is `assets/kadron-mark.svg`; PNG and Windows icon variants are shipped for the application window.
- Warm near-black (`#101317`) is the workspace ground. The rail uses `#171b20`; work surfaces use `#1d2227` and `#252b30`. Separators remain low-contrast rather than boxing every element. All colors, radii and motion constants live in the `Theme` singleton (`qml/Theme.qml`); components do not carry literal colors.
- On Windows the native caption is painted in the rail color with dark-mode chrome, so the title bar reads as part of the app.
- Acid-lime (`#c9f27a`) is reserved for current selection, primary action, progress, and the brand mark. Amber is the playhead and in-progress cue; red is for errors and destructive text.
- Segoe UI carries interface copy at compact desktop sizes. Timecodes keep steady widths and high contrast. Headings are clear but never compete with the media.
- Controls share an 8 px corner radius, visible keyboard focus, and short hover/selection transitions. Icons use one authored 1.6 px stroke vocabulary, drawn as vector shapes (`ToolIcon`), never rasterized canvases.

## Structure

- Persistent left rail groups the editor, media tasks, utilities, and publishing. The active destination has a filled state; the status at its foot distinguishes local use from server connection.
- A 68 px command bar names the task, identifies the source/project, and holds the editor's file actions. Export is the sole persistent primary action there.
- Editor: source monitor and transport in the center, clip inspector at right, sequence timeline across the bottom. Publish remains an explicit destination rather than a second row of editor tabs.
- The timeline shows the whole sequence: every clip is a block sized by its trimmed length, with a filmstrip and waveform. Dragging a block edge trims that clip (the scale holds still while trimming); dragging a block reorders it while the others make room; right-click offers split, duplicate and remove; Delete removes the selected clip. A trim only previews while dragging (the monitor shows the new edge, the cut part is dimmed, notches mark hidden media) and commits on release; Escape cancels. Every timeline edit is undoable (Ctrl+Z / Ctrl+Y). Ctrl + wheel zooms around the pointer, the wheel scrolls.
- The playhead is a draggable timecode flag in sequence time. While scrubbing it eases toward the pointer on a critically damped spring; during playback it follows the player directly. Scrub seeks are coalesced (one in flight, the latest wins) so the monitor always lands on the exact decoded frame. Play continues through the following clips.
- Media tools: a narrower, centered work form with a task-specific heading and concise processing description. File-based tools (audio, compression, GIF, PDF) open on a drop zone; options appear once a file is chosen, and dropping onto the page replaces it. The downloader accepts a dragged link. Download, PDF, QR, audio, compression, and GIF are marked on-device; Clips, Drop, and Shortener have dedicated server-backed destinations. Results and progress stay with the form. Audio is trimmed on its waveform: the selection is drawn in lime, handles and the Start/End fields stay in sync, and the selection plays (optionally looped) before converting. PDF editing is visual: pages render as thumbnails that can be selected, rotated, deleted, reordered by drag and previewed large, then saved as a new PDF. QR codes render live as options change. A pasted link shows its thumbnail, title and length before downloading; while it is looked up a skeleton holds the card's shape so nothing jumps.
- A narrow status strip reports actual work and errors. No permanent animation runs while idle.

## Motion and states

- Anything that moves or scales uses springs (`SnapSpring` for press feedback, `SmoothSpring` for travel) so interrupted gestures keep their momentum; colors cross-fade for 120–150 ms. The rail's active highlight travels between items; workspaces settle upward into place over ~180 ms. These transitions signal a state change, not a page-load performance.
- Modal dialogs blur and desaturate the workspace behind them. Closing unsaved work offers Save and close, Don't save, or Keep working. Every window close fades out before the window disappears.
- Progress fills animate between reported values. Export, local conversion, download, PDF processing, and publishing retain cancellation and textual stage feedback. GIF Studio selects its range on a filmstrip (drag handles or the whole range), loops the selection in the monitor, and previews the finished GIF.
- Empty media state offers import directly. Disabled operations remain visible but muted; errors stay legible and actionable. Keyboard focus is not replaced by hover alone.
- The minimum verified layout is 1020 × 680. At that width the transport compresses its volume control without hiding it; inspector scrolling preserves access to longer forms.

## Boundaries

The editor remains a single ordered sequence, not a multitrack timeline. Live Pi compatibility, macOS/Linux presentation, executable bundling in installers, and system reduced-motion preferences still need separate verification.
