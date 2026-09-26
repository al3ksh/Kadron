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

## Updates

Installed copies look for a newer GitHub release shortly after startup (at most once a day) and when the version in the sidebar is clicked. An update downloads the release's `Kadron-<version>-setup.exe`, checks its size and the SHA-256 GitHub publishes for it, and runs it silently once Kadron closes; **Restart to update** closes Kadron (asking about unsaved work as usual) and opens the new version. Portable copies link to the release page instead. For a release, tag it `v<version>` and attach the setup and the zip. `KADRON_UPDATE_URL` points the check at another endpoint and `KADRON_NO_UPDATE_CHECK` turns the automatic check off.

Download, Audio, Compress, GIF, PDF, and QR run on this device. Only Clips, Drop, and Shortener need a reachable Tools server URL entered in the app. Core tests use a local HTTP fixture and do not exercise a live server.
