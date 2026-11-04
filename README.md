# opus

[Opus](https://opus-codec.org) built for [onelf](https://github.com/QaidVoid/onelf)
packages: the codec library a bundle carries when something in it links
`libopus`, such as PulseAudio's `libsndfile`, without the megabytes a
distribution build adds.

## What is different from a distribution's Opus

- **No neural network features.** Deep packet loss concealment, DRED and
  OSCE are left out. Their model weights are what make Arch's library
  over 4 MB; without them it is about 420 KB. Applications that never
  enable those features, which is nearly all of them, see no change.
- **The same interface.** Custom modes stay on, as Arch builds them, so
  the library exports the same symbols under the same soname and can
  replace a distribution's copy in a build root.
- **Built on Void Linux**, against glibc 2.41, needing nothing newer than
  `GLIBC_2.29`.
- **`-O2` with link-time optimization**, and stripped.

## Releases

Tagged `v<opus version>-<release>`, where `release` counts rebuilds of
the same Opus. Each release carries, per architecture:

| Asset | Holds |
|-------|-------|
| `opus-<arch>.tar.zst` | `lib/` with `libopus` and its soname links, and the license under `share/licenses/opus` |

The tree unpacks over a build root's `/usr`, replacing the
distribution's `libopus` before a bundle is assembled.

## Building

```sh
podman run --rm -v "$PWD:/src" -w /src ghcr.io/void-linux/void-glibc:latest sh -c 'sh build.sh && sh test.sh'
```

`test.sh` checks the library's size, its custom-mode exports and its
version, and encodes and decodes a tone.

Versions and hashes are in `package.toml`; the
[control repository](https://github.com/onelf-pkgs/.github) bumps them
when upstream releases.
