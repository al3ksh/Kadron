# Kadron

<!-- impeccable:product-schema 1 -->

## Platform

Adaptive native desktop interface for Windows, macOS, and Linux. Windows is the only platform built and tested so far. Mobile is an open future decision.

## Stack

Qt 6 / QML and C++20. FFmpeg provides thumbnail extraction and local export. MLT integration for multitrack composition remains planned and unverified.

## Users

Someone editing and sharing short video, GIF, and audio on their own computer, sometimes publishing the result through a self-hosted Tools server.

## Product Purpose

Create and edit media locally with responsive preview, clear export progress, and explicit online sharing through Clips, Shortener, and Drop.

## Capabilities and Constraints

- Local files remain local until the user starts a share operation.
- The current editor imports one media file, trims a range, saves a project, and exports it locally. It does not yet support multitrack editing, effects, audio mixing, or GIF editing.
- Guest Clips, Shortener, and Drop publishing is integrated with the existing Tools API. The server address and desktop guest session are stored locally. Live-server compatibility has not yet been verified; tests use a local API fixture.
- Guest limits are 200 MB for Clips and 50 MB for Drop. Guest Clips expire after 24 hours, Drop after one hour, and Shortener links after seven days. Admin authentication is not implemented in Kadron.
- The app must keep its project format independent of the UI and media engine.
- Codec licensing and distributable FFmpeg builds must be resolved before shipping installers.

## Product Principles

- The timeline should make seeking, trimming, and moving selections distinct actions.
- Work in progress must be recoverable or clearly marked incomplete.
- Preview and export must eventually use the same project model.
- Server work should not block the editor UI, and local files should never upload without an explicit command.
