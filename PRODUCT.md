# Kadron

<!-- impeccable:product-schema 1 -->

## Platform

Desktop: Windows, macOS, Linux. Mobile is an open future decision.

## Stack

Qt 6 / QML and C++20, chosen after discussing a native media editor with the user. FFmpeg is used for local export in the first slice. MLT integration for multitrack composition remains planned and unverified.

## Users

Someone editing and sharing short video, GIF, and audio on their own computer, sometimes publishing the result through a self-hosted Tools server.

## Product Purpose

Create and edit media locally with responsive preview, clear export progress, and explicit online sharing through Clips, Shortener, and Drop.

## Capabilities and Constraints

- Local files remain local until the user starts a share operation.
- The first slice imports one media file, trims a range, saves a project, and exports it locally.
- Clips, Shortener, and Drop live on the existing Tools server. Their native integration needs a separate authenticated client and is not present in the first slice.
- The app must keep its project format independent of the UI and media engine.
- Codec licensing and distributable FFmpeg builds must be resolved before shipping installers.

## Product Principles

- The timeline should make seeking, trimming, and moving selections distinct actions.
- Work in progress must be recoverable or clearly marked incomplete.
- Preview and export must eventually use the same project model.
