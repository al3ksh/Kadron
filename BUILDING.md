# Building Kadron

Requirements: CMake 3.24+, C++20 compiler, Qt 6.8+ (Quick, QuickControls2, Multimedia, Network, Concurrent, Test), Ninja, and FFmpeg/FFprobe on `PATH` or `KADRON_FFMPEG` and `KADRON_FFPROBE` set to the respective executables. The local tools also use yt-dlp (Download), qpdf and poppler's `pdftoppm` (PDF Tools), and qrencode (QR Code); `KADRON_PDFTOPPM` and similar variables override their lookup. Kadron keeps its own updatable yt-dlp in `%LOCALAPPDATA%/Kadron/bin` and prefers it over `PATH`.

Windows with MSYS2 UCRT64:

```powershell
cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH=C:/msys64/ucrt64 -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j 4
$env:KADRON_FFMPEG='C:\msys64\ucrt64\bin\ffmpeg.exe'
C:\msys64\ucrt64\bin\ctest.exe --test-dir build --output-on-failure
```

Launch `build/kadron.exe` with the MSYS2 UCRT64 runtime DLL directory on `PATH`. A local media file or `.kadr` project may be passed as the first argument.

Kadron saves `.kadr` projects in version 2 with ordered clips and opens version 1 projects. Multi-clip export requires both FFmpeg and FFprobe; temporary segments are created beside the destination and removed after success or cancellation.

Windows is the only platform verified.

## Windows installer

`packaging/windows/package.sh` (Git Bash or an MSYS2 shell; needs `mingw-w64-ucrt-x86_64-nsis` as well) makes a Release build and writes to `dist/`:

- `Kadron-<version>-setup.exe`: per-user NSIS installer into `%LOCALAPPDATA%\Programs\Kadron`, no administrator prompt. Start menu entry, optional desktop shortcut, optional `.kadr` association, and an uninstaller that removes exactly the files it installed.
- `Kadron-<version>-win64-portable.zip`: the same folder to unpack anywhere.

The package holds the Qt runtime (via `windeployqt`, with a `qt.conf` for MSYS2's layout), the UCRT64 DLLs everything needs, and `ffmpeg`, `ffprobe`, `qpdf`, `pdftoppm`, `qrencode` and the standalone `yt-dlp.exe` in `bin/`. `licenses/` has Kadron's license, the license files of every bundled MSYS2 package and `THIRD-PARTY.txt` with their versions and where their sources are. The bundled FFmpeg is MSYS2's GPL v3-or-later build, which matches Kadron's GPL-3.0; some of its codecs (H.264/H.265 encoders among them) are patent-encumbered in some countries.

The version comes from `project(Kadron VERSION ...)` in `CMakeLists.txt`.

## GPU encoding

Shortly after startup Kadron tries a tiny test encode with `h264_nvenc`, `h264_qsv` and `h264_amf`; the ones that succeed appear in the editor's **Encoder** list. **Auto** uses the first of them, else the CPU (`libx264`). The choice is remembered. A GPU encode that fails is retried on the CPU. `KADRON_NO_GPU` skips detection. The core test `hardwareEncoders` exports a clip with every encoder found on the machine.

## Startup intro

While the main window loads, Kadron plays a short intro (`qml/Intro.qml`): the trim handles of a range strip fold into the mark. It is a single fragment shader (`shaders/intro.frag`, compiled by `qt_add_shaders`) whose clock is driven by `UniformAnimator`s on the render thread, so it stays smooth while the UI thread is busy (loading QtMultimedia alone takes most of a second). The intro holds on the wordmark until the app is ready; the main window is then shown cloaked, drawn once and uncloaked over the intro, so there is no blank frame. A click or key skips ahead. It follows the theme and accent and can be turned off in the Appearance panel; `KADRON_NO_INTRO` skips it for one run. `KADRON_SCREENSHOT_INTRO=<seconds>` (with `KADRON_SCREENSHOT`) saves that moment of the intro instead of the app.

`design/intro/kadron-intro.html` is the same animation on a 2D canvas; `design/intro/render.js` renders it frame by frame to an MP4 (needs `puppeteer-core`, Chrome and FFmpeg).

## Updates

Installed copies look for a newer GitHub release shortly after startup (at most once a day) and when the version in the sidebar is clicked. An update downloads the release's `Kadron-<version>-setup.exe`, checks its size and the SHA-256 GitHub publishes for it, and runs it silently once Kadron closes; **Restart to update** closes Kadron (asking about unsaved work as usual) and opens the new version. Portable copies link to the release page instead. For a release, tag it `v<version>` and attach the setup and the zip. `KADRON_UPDATE_URL` points the check at another endpoint and `KADRON_NO_UPDATE_CHECK` turns the automatic check off.

Download, Audio, Compress, GIF, PDF, and QR run on this device. Only Clips, Drop, and Shortener need a reachable Tools server URL entered in the app. Core tests use a local HTTP fixture and do not exercise a live server.
