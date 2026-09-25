# Kadron Interface

## Purpose

An editing workspace for repeated local media work. The footage leads; controls stay compact and predictable.

## Visual System

- Neutral charcoal work surfaces (`#181a1b`, `#202324`, `#222527`) around a near-black preview (`#0e1011`).
- Desaturated cyan (`#a9cfd0`) marks primary actions and selection. Warm amber (`#e8b57e`) marks the playhead and work in progress. Red is reserved for errors and destructive actions.
- Segoe UI at 10-14 px for controls and metadata, with 17 px only for the app name. No decorative display type or gradients.
- Four-pixel control radii, thin separators, minimal elevation. Buttons, fields, and panels follow one vocabulary.

## Workspace

- 54 px top command bar: project identity, open/import/save, export.
- A compact workspace strip switches between Edit, Download, Audio, Compress, GIF, PDF, QR, and Publish. Tool screens are forms rather than a dashboard.
- Left media bin: the imported file, first-frame thumbnail, project location.
- Center preview: real video or immediate first-frame thumbnail, then one transport row. Seeking happens on the timeline, not on a duplicate slider.
- Right inspector: Edit and Publish modes. Publish keeps server connection, file sharing, short links, progress, errors, and result URL together. The inspector alone scrolls on short windows.
- Full-width bottom timeline: separate seek lane and trim lane. Click to seek; drag in/out handles to resize; drag the center grip to move the range. Amber playhead never competes with white trim handles.
- 30 px status strip for current work and errors.
- Audio, compression, and GIF screens show local progress and output weight. Network screens show queue/processing state and require an explicit save of the server result.

## Interaction Rules

- Replacing an unsaved project requires confirmation.
- Export and upload remain explicit, cancellable operations with visible progress.
- Server publishing uses a separate guest session; the app never silently uploads local media.
- Controls must remain available at the 1020 x 680 minimum window size, with inspector scrolling when necessary.
