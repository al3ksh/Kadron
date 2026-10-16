# Kadron

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Stack

Qt 6 / QML and C++20, built with MSYS2 UCRT64. FFmpeg/FFprobe provide thumbnails, preview decoding (Qt Multimedia's FFmpeg backend), sequence export, audio conversion, image/video compression, Reframe and GIF encoding. yt-dlp handles local URL downloads; qpdf handles PDF page operations and poppler's pdftoppm renders page thumbnails for the visual PDF editor; qrencode generates QR images. Qt paints images into PDF documents. The Windows installer (NSIS) and portable zip bundle all of these.

## Users

Someone editing and sharing short video, GIF, and audio on their own computer, sometimes publishing the result through a self-hosted Tools server.

## Product Purpose

Assemble, preview, trim, download, and process media locally with visible progress. Publish only through a configured self-hosted Tools server.

## Capabilities and Constraints

- The native desktop interface targets Windows, macOS, and Linux. Only Windows is built, packaged and tested so far; mobile remains a future decision.
- Local files remain local until the user starts a share operation.
- The editor assembles an ordered sequence of local video or audio clips on one video track. Each clip has its own trim range, speed, volume, rotation, crop and colour; clips can be split, reordered and joined with a cut, a fade through black or a crossfade. Above the clips sits a text track, below them an audio track for music and sounds with fades and ducking. Markers, freeze frames and silence removal work on the same model. Preview advances across the entire sequence.
- The project format is versioned JSON (`.kadr`, currently v5/v6) and opens every earlier version. It stays independent of the UI and media engine; unsaved work is copied aside for crash recovery.
- MP4 sequence export normalizes canvas, frame rate, video and audio codecs before joining clips. Audio-only clips render over black, and silent video gets a silent audio track. Export runs on NVENC, Quick Sync or AMF when available and falls back to the CPU. Exports queue, can carry markers as chapters and an optional logo, and a single trimmed clip can be cut losslessly. Multiple video tracks are not supported.
- Audio conversion supports MP3, AAC, Opus, WAV, and FLAC. Image/video compression, Reframe and GIF generation run locally. Target-size mode retries encoding and fails if the limit cannot be reached without truncation. GIF Studio previews the source and the finished GIF.
- The downloader runs yt-dlp and FFmpeg on this device, with a local save path selected before the job starts. Kadron keeps its own copy of yt-dlp up to date. PDF page operations use qpdf, images-to-PDF use Qt, and QR generation uses qrencode locally.
- Only guest Clips, Shortener, and Drop use the existing Tools API. The server address and desktop guest session are stored locally. Tests use a local API fixture.
- Local files stay on the device until an explicit Clips or Drop upload. A URL download contacts its original source directly from this device, and the updater reads GitHub Releases.
- Guest limits are 200 MB for Clips and 50 MB for Drop. Guest Clips expire after 24 hours, Drop after one hour, and Shortener links after seven days. Admin authentication is not implemented in Kadron.
- Kadron is GPLv3. The bundled FFmpeg is a GPLv3 build without nonfree components; the installer ships every bundled package's license and source location. Releases are not code-signed.

## Product Principles

- The timeline should make seeking, trimming, and moving selections distinct actions.
- Edits that remove material wait for confirmation and stay undoable.
- Work in progress must be recoverable or clearly marked incomplete.
- Preview and export use the same project model.
- Server work should not block the editor UI, and local files should never upload without an explicit command.
