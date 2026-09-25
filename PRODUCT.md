# Kadron

<!-- impeccable:product-schema 1 -->

## Platform

Adaptive native desktop interface for Windows, macOS, and Linux. Windows is the only platform built and tested so far. Mobile is an open future decision.

## Stack

Qt 6 / QML and C++20. FFmpeg/FFprobe provide thumbnail extraction, local export, audio conversion, image/video compression, and GIF encoding. MLT integration for multitrack composition remains planned and unverified.

## Users

Someone editing and sharing short video, GIF, and audio on their own computer, sometimes publishing the result through a self-hosted Tools server.

## Product Purpose

Assemble, preview, trim, and process media locally with visible progress. Download and publish through a configured self-hosted Tools server.

## Capabilities and Constraints

- Local files remain local until the user starts a share operation.
- The editor assembles an ordered sequence of local video or audio clips. Each clip has its own trim range; a clip can be split and reordered. Preview advances across the entire sequence. Project format v2 preserves the sequence and can open legacy v1 projects.
- MP4 sequence export normalizes canvas, frame rate, video and audio codecs before joining clips. Audio-only clips render over black, and silent video gets a silent audio track. This is a single-track sequence, not multitrack editing; effects, transitions, audio mixing, and GIF editing remain future work.
- Audio conversion supports MP3, WAV, FLAC, and Opus. Image/video compression and GIF generation run locally. Target-size mode retries encoding and fails if the limit cannot be reached without truncation.
- Downloader, PDF operations, QR generation, and guest Clips/Shortener/Drop use the existing Tools API. The server address and desktop guest session are stored locally. Live-server compatibility has not yet been verified; tests use a local API fixture.
- PDF documents are uploaded to the server. Local media is only uploaded after an explicit publish or PDF action; URL downloads are handled by the server.
- Guest limits are 200 MB for Clips and 50 MB for Drop. Guest Clips expire after 24 hours, Drop after one hour, and Shortener links after seven days. Admin authentication is not implemented in Kadron.
- The app must keep its project format independent of the UI and media engine.
- Codec licensing and distributable FFmpeg builds must be resolved before shipping installers.

## Product Principles

- The timeline should make seeking, trimming, and moving selections distinct actions.
- Work in progress must be recoverable or clearly marked incomplete.
- Preview and export must eventually use the same project model.
- Server work should not block the editor UI, and local files should never upload without an explicit command.
