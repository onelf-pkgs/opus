#!/bin/sh
# Verifies the Opus tree build.sh wrote: the library stays small, exports
# the custom-mode API the distribution builds do, reports the packaged
# version, and encodes and decodes audio. Runs in the same container,
# right after it.
#
# Usage: test.sh
set -eu
cd "$(dirname "$0")"

arch=$(uname -m)
version=$(python3 -c 'import tomllib; print(tomllib.load(open("package.toml", "rb"))["sources"]["opus"]["version"])')

fail() {
    echo "opus-$arch: $*" >&2
    exit 1
}

test_dir=$PWD/build/test
tree=$test_dir/tree
rm -rf "$test_dir"
mkdir -p "$tree"
tar --zstd -xf "dist/opus-$arch.tar.zst" -C "$tree"

[ -f "$tree/share/licenses/opus/COPYING" ] || fail "the tree carries no license"
[ -e "$tree/lib/libopus.so.0" ] || fail "the tree has no libopus.so.0"
lib=$(readlink -f "$tree/lib/libopus.so.0")

size=$(stat -c %s "$lib")
[ "$size" -lt 1048576 ] || fail "libopus is $size bytes, so the neural network features are back"

nm -D --defined-only "$lib" | grep -q ' opus_custom_encoder_create$' ||
    fail "libopus does not export the custom-mode API"

cat > "$test_dir/roundtrip.c" <<'EOF'
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <opus.h>

#define RATE 48000
#define FRAME 960
#define FRAMES 50

int main(int argc, char **argv)
{
    const char *version = opus_get_version_string();
    if (argc < 2 || !strstr(version, argv[1])) {
        fprintf(stderr, "version %s is not %s\n", version, argc < 2 ? "?" : argv[1]);
        return 1;
    }
    int err;
    OpusEncoder *enc = opus_encoder_create(RATE, 2, OPUS_APPLICATION_AUDIO, &err);
    if (err != OPUS_OK)
        return 2;
    OpusDecoder *dec = opus_decoder_create(RATE, 2, &err);
    if (err != OPUS_OK)
        return 3;
    float in[FRAME * 2], out[FRAME * 2];
    unsigned char packet[4000];
    double in_energy = 0, out_energy = 0;
    for (int f = 0; f < FRAMES; f++) {
        for (int i = 0; i < FRAME; i++) {
            float s = 0.5f * sinf(2.0f * (float)M_PI * 440.0f * (float)(f * FRAME + i) / RATE);
            in[2 * i] = in[2 * i + 1] = s;
        }
        int len = opus_encode_float(enc, in, FRAME, packet, sizeof packet);
        if (len <= 0)
            return 4;
        int got = opus_decode_float(dec, packet, len, out, FRAME, 0);
        if (got != FRAME)
            return 5;
        if (f >= FRAMES / 2) {
            for (int i = 0; i < FRAME * 2; i++) {
                in_energy += (double)in[i] * in[i];
                out_energy += (double)out[i] * out[i];
            }
        }
    }
    double ratio = out_energy / in_energy;
    if (ratio < 0.8 || ratio > 1.25) {
        fprintf(stderr, "decoded energy is %.2f of the input\n", ratio);
        return 6;
    }
    opus_encoder_destroy(enc);
    opus_decoder_destroy(dec);
    printf("%s round trip ok\n", version);
    return 0;
}
EOF
cc -O2 -o "$test_dir/roundtrip" "$test_dir/roundtrip.c" \
    -I build/work/stage/usr/include/opus \
    -L "$tree/lib" -l:libopus.so.0 -lm -Wl,-rpath,"$tree/lib"
"$test_dir/roundtrip" "$version"

echo "opus-$arch: $size bytes, custom modes, round trip ok"
