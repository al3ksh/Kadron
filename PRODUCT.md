# Kadron

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Stack

Qt 6 / QML and C++20. FFmpeg/FFprobe provide thumbnail extraction, local export, audio conversion, image/video compression, and GIF encoding. yt-dlp handles local URL downloads; qpdf handles local PDF page operations and poppler's pdftoppm renders page thumbnails for the visual PDF editor; qrencode generates QR images locally. Qt paints images into PDF documents. MLT integration for multitrack composition remains planned and unverified.

## Users

Someone editing and sharing short video, GIF, and audio on their own computer, sometimes publishing the result through a self-hosted Tools server.

## Product Purpose

Assemble, preview, trim, download, and process media locally with visible progress. Publish only through a configured self-hosted Tools server.

## Capabilities and Constraints

- The native desktop interface targets Windows, macOS, and Linux. Only Windows is built and tested so far; mobile remains a future decision.
- Local files remain local until the user starts a share operation.
- The editor assembles an ordered sequence of local video or audio clips. Each clip has its own trim range; a clip can be split and reordered. Preview advances across the entire sequence. Project format v2 preserves the sequence and can open legacy v1 projects.
- MP4 sequence export normalizes canvas, frame rate, video and audio codecs before joining clips. Audio-only clips render over black, and silent video gets a silent audio track. This is a single-track sequence, not multitrack editing; effects, transitions, audio mixing, and GIF editing remain future work.
- Audio conversion supports MP3, WAV, FLAC, and Opus. Image/video compression and GIF generation run locally. Target-size mode retries encoding and fails if the limit cannot be reached without truncation. GIF Studio previews the source and the finished GIF.
- The downloader runs yt-dlp and FFmpeg on this device, with a local save path selected before the job starts. PDF page operations use qpdf, images-to-PDF use Qt, and QR generation uses qrencode locally. These tools require local executables or bundled binaries; installation packaging is not complete.
- Only guest Clips, Shortener, and Drop use the existing Tools API. The server address and desktop guest session are stored locally. Live-server compatibility has not yet been verified; tests use a local API fixture.
- Local files stay on the device until an explicit Clips or Drop upload. A URL download contacts its original source directly from this device.
- Guest limits are 200 MB for Clips and 50 MB for Drop. Guest Clips expire after 24 hours, Drop after one hour, and Shortener links after seven days. Admin authentication is not implemented in Kadron.
- The app must keep its project format independent of the UI and media engine.
- Codec licensing and distributable FFmpeg builds must be resolved before shipping installers.

## Product Principles

- The timeline should make seeking, trimming, and moving selections distinct actions.
- Work in progress must be recoverable or clearly marked incomplete.
- Preview and export must eventually use the same project model.
- Server work should not block the editor UI, and local files should never upload without an explicit command.
