# Kadron Interface

## Direction

A focused post-production desk, not a dashboard. The footage and the current task lead; navigation and status stay calm. Controls react quickly without making users wait for decorative motion.

## Identity

- The Kadron mark is a cut K: two edit strokes converge on a white pivot. The vector source is `assets/kadron-mark.svg`; PNG and Windows icon variants are shipped for the application window.
- Warm near-black (`#101317`) is the workspace ground. The rail uses `#181c21`; work surfaces use `#1d2227` and `#252b30`. Separators remain low-contrast rather than boxing every element.
- Acid-lime (`#c9f27a`) is reserved for current selection, primary action, progress, and the brand mark. Amber is the playhead and in-progress cue; red is for errors and destructive text.
- Segoe UI carries interface copy at compact desktop sizes. Timecodes keep steady widths and high contrast. Headings are clear but never compete with the media.
- Controls share an 8 px corner radius, visible keyboard focus, and short hover/selection transitions. Icons use one authored 1.6 px stroke vocabulary.

## Structure

- Persistent left rail groups the editor, media tasks, utilities, and publishing. The active destination has a filled state; the status at its foot distinguishes local use from server connection.
- A 68 px command bar names the task, identifies the source/project, and holds the editor's file actions. Export is the sole persistent primary action there.
- Editor: ordered clip list at left, source monitor and transport in the center, contextual trim/publish inspector at right, timeline across the bottom. Publish remains an explicit destination rather than a second row of editor tabs.
- The timeline playhead is a draggable timecode flag with a pointer anchored to the exact source position, including the first and last frame. The source playhead may sit outside the selected in/out range while reviewing footage; Play starts from the in point when outside that range.
- Media tools: a narrower, centered work form with a task-specific heading and concise processing description. Local and server operations are explicitly labeled; results and progress stay with the form.
- A narrow status strip reports actual work and errors. No permanent animation runs while idle.

## Motion and states

- Navigation and button surfaces interpolate for 140–150 ms; switching workspaces or inspector modes reveals the new task for 160–180 ms. These transitions signal a state change, not a page-load performance.
- Progress fills animate between reported values. Export, local conversion, download, and publishing retain cancellation and textual stage feedback.
- Empty media state offers import directly. Disabled operations remain visible but muted; errors stay legible and actionable. Keyboard focus is not replaced by hover alone.
- The minimum verified layout is 1020 × 680. At that width the transport compresses its volume control without hiding it; inspector scrolling preserves access to longer forms.

## Boundaries

The editor remains a single ordered sequence, not a multitrack timeline. Live Pi compatibility, macOS/Linux presentation, installation packaging, and system reduced-motion preferences still need separate verification.
