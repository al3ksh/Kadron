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

There is no installer or bundled FFmpeg yet. Windows is the only platform verified. Qt and FFmpeg codec distribution terms must be reviewed before packaging binaries.

Download, Audio, Compress, GIF, PDF, and QR run on this device. Only Clips, Drop, and Shortener need a reachable Tools server URL entered in the app. Core tests use a local HTTP fixture and do not exercise a live server.
