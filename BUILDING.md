# Building Kadron

Requirements: CMake 3.24+, C++20 compiler, Qt 6.8+ (Quick, QuickControls2, Multimedia, Network, Test), Ninja, and FFmpeg/FFprobe on `PATH` or `KADRON_FFMPEG` set to the FFmpeg executable.

Windows with MSYS2 UCRT64:

```powershell
cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH=C:/msys64/ucrt64 -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j 4
$env:KADRON_FFMPEG='C:\msys64\ucrt64\bin\ffmpeg.exe'
C:\msys64\ucrt64\bin\ctest.exe --test-dir build --output-on-failure
```

Launch `build/kadron.exe` with the MSYS2 UCRT64 runtime DLL directory on `PATH`. A local media file or `.kadr` project may be passed as the first argument.

There is no installer or bundled FFmpeg yet. Windows is the only platform verified. Qt and FFmpeg codec distribution terms must be reviewed before packaging binaries.
