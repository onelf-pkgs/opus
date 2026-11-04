#!/bin/sh
# Builds Opus for this machine's architecture into dist/:
#
#   opus-<arch>.tar.zst   lib/ with libopus and its soname links, and
#                         share/licenses/opus/COPYING
#
# The tree unpacks over a build root's /usr, so a bundle built there
# carries this library instead of the distribution's.
#
# Usage: build.sh
#
# Runs as root in a Void Linux (glibc) container with this directory as
# the working directory.
set -eu
cd "$(dirname "$0")"

arch=$(uname -m)

xbps-install -Syu xbps > /dev/null
xbps-install -Syu > /dev/null
xbps-install -y base-devel meson ninja pkg-config python3 curl findutils tar zstd > /dev/null

toml() {
    python3 -c '
import sys, tomllib
value = tomllib.load(open("package.toml", "rb"))
for key in sys.argv[1].split("."):
    value = value[key]
print(value)
' "$1"
}

# fetch <source>: download a source into build/src once, and check it.
fetch() {
    version=$(toml "sources.$1.version")
    url=$(toml "sources.$1.url" | sed "s/{version}/$version/g")
    file=build/src/${url##*/}
    mkdir -p build/src
    if [ ! -f "$file" ]; then
        curl -fL --retry 3 -o "$file.part" "$url"
        mv "$file.part" "$file"
    fi
    echo "$(toml "sources.$1.sha256")  $file" | sha256sum -c - > /dev/null
    echo "$file"
}

work=$PWD/build/work
jobs=${JOBS:-$(nproc)}

opus_source=$(fetch opus)
rm -rf "$work"
mkdir -p "$work/opus"
tar -xzf "$opus_source" -C "$work/opus" --strip-components=1

# The options Arch builds with, less deep PLC, DRED and OSCE: the neural
# network features whose model weights take the library from about half
# a megabyte to over four. Custom modes stay on, so the library exports
# the same symbols as the distribution builds it replaces.
meson setup "$work/build" "$work/opus" \
    --prefix=/usr --libdir=lib --buildtype=release -D optimization=2 -D b_lto=true \
    -D b_ndebug=true \
    -D asm=disabled -D custom-modes=true \
    -D deep-plc=disabled -D dred=disabled -D osce=disabled \
    -D extra-programs=disabled -D tests=disabled -D docs=disabled
meson compile -C "$work/build" -j "$jobs"
DESTDIR="$work/stage" meson install -C "$work/build" --quiet

tree=$work/tree
mkdir -p "$tree/lib" "$tree/share/licenses/opus"
cp -a "$work/stage/usr/lib"/libopus.so* "$tree/lib/"
cp "$work/opus/COPYING" "$tree/share/licenses/opus/COPYING"
find "$tree/lib" -name 'libopus.so*' -type f -exec strip --strip-unneeded {} +

rm -rf dist
mkdir -p dist
tar --zstd -cf "dist/opus-$arch.tar.zst" --sort=name --owner=0 --group=0 \
    -C "$tree" .

ls -l dist
