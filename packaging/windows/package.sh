#!/usr/bin/env bash
# Builds a Windows release of Kadron and packs it into an NSIS installer and a
# portable zip under dist/.
#
# Requires MSYS2 UCRT64 (default C:/msys64, override with MSYS2_ROOT) with the
# packages listed in README.md plus mingw-w64-ucrt-x86_64-nsis.
# Run from Git Bash or an MSYS2 shell:  packaging/windows/package.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
msys=${MSYS2_ROOT:-/c/msys64}
ucrt=$msys/ucrt64
# windeployqt runs qmlimportscanner by name; MSYS2 keeps it in share/qt6/bin.
export PATH="$ucrt/bin:$ucrt/share/qt6/bin:$msys/usr/bin:$PATH"

version=$(sed -n 's/^project(Kadron VERSION \([0-9.]*\).*/\1/p' "$root/CMakeLists.txt")
build=$root/build-release
dist=$root/dist
stage=$dist/Kadron
echo "Packaging Kadron $version"

# 1. Release build (tests run in the regular Debug build).
cmake -S "$root" -B "$build" -G Ninja -DCMAKE_PREFIX_PATH="$ucrt" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF > /dev/null
cmake --build "$build" -j 8

# 2. Application and Qt runtime.
rm -rf "$stage"
mkdir -p "$stage/bin" "$stage/licenses"
cp "$build/kadron.exe" "$stage/"
windeployqt6 --qtpaths "$ucrt/bin/qtpaths6.exe" --release --qmldir "$root/qml" --no-translations --no-system-d3d-compiler --no-opengl-sw \
    --no-compiler-runtime "$stage/kadron.exe" > /dev/null
# Kadron always uses the Basic style (main.cpp); drop the others.
for style in FluentWinUI3 Fusion Imagine Material Universal Windows; do
    rm -rf "$stage/qml/QtQuick/Controls/$style"
    rm -f "$stage"/Qt6QuickControls2"$style"*.dll
done
# MSYS2's Qt looks for plugins and QML modules under share/qt6/ relative to the
# prefix; point both at the deployed layout instead.
printf '[Paths]\r\nPrefix = .\r\nPlugins = .\r\nQmlImports = qml\r\n' > "$stage/qt.conf"

# 3. Local tools. They sit in bin/ and use the DLLs next to kadron.exe, which
#    Kadron puts on PATH for its child processes.
for tool in ffmpeg ffprobe qpdf pdftoppm qrencode; do
    cp "$ucrt/bin/$tool.exe" "$stage/bin/"
done
# The MSYS2 yt-dlp is a Python script; ship the standalone build instead.
# Kadron keeps its own updatable copy, so this is only the first-run fallback.
curl -fsSL -o "$stage/bin/yt-dlp.exe" https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe

# 4. Every DLL the executables and Qt plugins load from UCRT64, repeated until
#    nothing new turns up.
while :; do
    added=0
    while IFS= read -r dll; do
        name=$(basename "$dll")
        if [ ! -e "$stage/$name" ]; then
            cp "$ucrt/bin/$name" "$stage/"
            added=1
        fi
    done < <(find "$stage" -iname '*.exe' -o -iname '*.dll' | grep -vi 'yt-dlp' | while read -r file; do
                 ldd "$file" 2>/dev/null | awk '$3 ~ /^\/ucrt64\/bin\// { print $3 }'
             done | sort -u)
    [ "$added" = 0 ] && break
done

# 5. Licenses: Kadron's own, then the license files of every MSYS2 package a
#    shipped file came from, with versions and where to get their sources.
cp "$root/LICENSE" "$stage/LICENSE.txt"
packages=$(find "$stage" -iname '*.exe' -o -iname '*.dll' | grep -vi 'yt-dlp\|kadron.exe' | while read -r file; do
               pacman -Qqo "/ucrt64/bin/$(basename "$file")" 2>/dev/null \
                   || pacman -Qqo "/ucrt64/share/qt6/${file#"$stage"/}" 2>/dev/null || true
           done | sort -u)
{
    echo "Kadron $version bundles the following third-party software."
    echo "Each package's license files are in the folder of the same name."
    echo "Sources for every MSYS2 package: https://packages.msys2.org/ (search the package name),"
    echo "or https://github.com/msys2/MINGW-packages for the build recipes."
    echo
    for package in $packages; do
        pacman -Q "$package"
        short=${package#mingw-w64-ucrt-x86_64-}
        if [ -d "$ucrt/share/licenses/$short" ]; then
            cp -r "$ucrt/share/licenses/$short" "$stage/licenses/$short"
        fi
    done
    echo "yt-dlp (standalone build from https://github.com/yt-dlp/yt-dlp) - The Unlicense"
} > "$stage/licenses/THIRD-PARTY.txt"

# 6. Installer and portable zip. windeployqt leaves some empty folders; they
#    would outlive the uninstaller, which only knows the shipped files.
find "$stage" -type d -empty -delete
(cd "$stage" && find . -type f | sed 's|^\./||' | sort) > "$dist/files.txt"
python - "$dist/files.txt" "$dist/uninstall-files.nsh" <<'PY'
import sys, posixpath
files = [line.strip() for line in open(sys.argv[1]) if line.strip()]
dirs = set()
for path in files:
    parent = posixpath.dirname(path)
    while parent:
        dirs.add(parent)
        parent = posixpath.dirname(parent)
with open(sys.argv[2], 'w', newline='\r\n') as out:
    for path in files:
        out.write('Delete "$INSTDIR\\%s"\n' % path.replace('/', '\\'))
    for folder in sorted(dirs, key=lambda d: d.count('/'), reverse=True):
        out.write('RMDir "$INSTDIR\\%s"\n' % folder.replace('/', '\\'))
PY
size_kb=$(du -sk "$stage" | cut -f1)
makensis -V2 -DVERSION="$version" -DROOT="$(cygpath -w "$root")" -DSTAGE="$(cygpath -w "$stage")" \
    -DDIST="$(cygpath -w "$dist")" -DSIZE_KB="$size_kb" "$(cygpath -w "$root/packaging/windows/kadron.nsi")"

rm -f "$dist/Kadron-$version-win64-portable.zip"
(cd "$dist" && bsdtar -a -cf "Kadron-$version-win64-portable.zip" Kadron)

echo
ls -la "$dist"/Kadron-"$version"-*
