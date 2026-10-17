# photocraft-flake

A Nix flake that packages [PhotoCraft](https://github.com/storytold/photocraft), a native,
open-source image editor written in Rust (layers, masks, adjustment layers, PSD support).

The flake builds PhotoCraft from source and tracks upstream's default branch through a flake
input. PhotoCraft itself is developed upstream, and upstream describes it as early alpha, so
expect some bugs!

## Quick start

Run it without installing:

```sh
nix run github:NAXLAB/photocraft-flake                     # the desktop app
nix run github:NAXLAB/photocraft-flake#photocraft-xwayland # the desktop app, forced to XWayland
nix run github:NAXLAB/photocraft-flake#cli                 # photocraft-cli
```

Or install it into your user profile:

```sh
nix profile install github:NAXLAB/photocraft-flake
```

### Things to know first

- **There is no binary cache.** This flake compiles Photocraft from source.
- **You need a recent nixpkgs.** Upstream requires Rust 1.95 or newer. Use `nixos-unstable` (or
  anything with a new enough `rustc`); an older stable channel will fail to build.
- **The build needs network access at evaluation time.** Some of upstream's cargo dependencies
  are git repositories (`storytold/craft-libs`, `storytold/winprint.rs`), which Nix fetches
  while evaluating.
- **It tracks upstream's default branch.** `flake.lock` pins one upstream commit, so you get the
  same build until you update. The version is shown as `<upstream version>-unstable-<commit date>`.

```sh
nix flake update photocraft-src   # in a checkout of this repo: move to upstream's latest commit
nix flake update photocraft       # in your own flake: pick up the latest version of this flake
```

## Install on NixOS

Add the flake as an input, and make sure your modules receive `inputs` (for example through
`specialArgs = { inherit inputs; };`):

```nix
# flake.nix
inputs.photocraft = {
  url                     = "github:NAXLAB/photocraft-flake";
  inputs.nixpkgs.follows  = "nixpkgs";
};
```

```nix
# any module that takes `inputs` in its arguments
environment.systemPackages = [
  inputs.photocraft.packages.${pkgs.stdenv.hostPlatform.system}.default
];
```

Or use the overlay and write `pkgs.photocraft`:

```nix
nixpkgs.overlays = [ inputs.photocraft.overlays.default ];
environment.systemPackages = [ pkgs.photocraft ];
```

Open, Save and Export dialogs go through the XDG desktop portal, so you need a portal backend
that provides a file chooser (for example `xdg-desktop-portal-gnome` or
`xdg-desktop-portal-gtk`) and `hardware.graphics.enable = true` for Vulkan/EGL. Without a
portal, the dialogs silently fail to appear.

## Drag-and-drop and pen tablets on Wayland

PhotoCraft has no native drag-and-drop on Wayland yet, and its pen-tablet support (pressure and
tilt) is X11-only. The `photocraft-xwayland` package runs the app under XWayland even in a
Wayland session (it unsets `WAYLAND_DISPLAY`), which enables both:

```nix
environment.systemPackages = [
  inputs.photocraft.packages.${pkgs.stdenv.hostPlatform.system}.photocraft-xwayland
];
```

Or, with the overlay: `pkgs.photocraft.override { x11 = true; }`.

This needs an X server in the session, so `DISPLAY` must be set. Under niri, install
`xwayland-satellite`. XWayland apps can look slightly blurry on HiDPI or fractionally scaled
outputs. If you stay on native Wayland, File > Open, or pasting an image with Ctrl+V, still
works.

## Outputs

| Output | What it is |
| --- | --- |
| `packages.<system>.default` / `photocraft` | The desktop app and `photocraft-cli` |
| `packages.<system>.photocraft-xwayland` | The same, forced to run under XWayland |
| `apps.<system>.default` | Runs `photocraft` |
| `apps.<system>.cli` | Runs `photocraft-cli` |
| `overlays.default` | Adds `pkgs.photocraft` |
| `devShells.<system>.default` | Rust toolchain extras plus the runtime libraries, for hacking on upstream |

For the dev shell, check out upstream and run `nix develop github:NAXLAB/photocraft-flake`
inside it, then `cargo run --release -p photocraft`. `LD_LIBRARY_PATH` is set so the windowing
and GPU libraries are found.

## What is in the package

- `photocraft` and `photocraft-cli` binaries, built with upstream's `heif` feature (HEIC/HEIF
  decoding, pure Rust) as in its official Linux builds.
- Desktop entry, MIME definitions, AppStream metadata and icons from upstream's
  `packaging/linux`.
- Runtime libraries (xkbcommon, Wayland, X11, Vulkan, EGL, libdbus) added to the binary's
  RPATH, because winit, wgpu and rfd load them with `dlopen`.
- `PHOTOCRAFT_SKIP_LIB_CHECK=1` set in a wrapper. Upstream's start-up check looks for those
  libraries through `ldconfig`, which does not exist on NixOS, and would otherwise print a
  false warning.

Upstream's test suite is not run during the build: it includes GPU snapshot tests and corpus
tests that download files, none of which work in the Nix sandbox.

## Troubleshooting

If the build fails, Nix may print only "build failed" and then wait for other jobs. Re-run with
logs to see the real error:

```sh
nix build -L --keep-going github:NAXLAB/photocraft-flake
nix log github:NAXLAB/photocraft-flake#photocraft   # log of the last failed build
```

Common causes: a `nixpkgs` whose `rustc` is older than upstream requires, an upstream commit
that does not build (try `nix flake update photocraft-src` or pin an older one), or a new system
library dependency upstream. Please open an issue with the end of the log.

## Limitations

- The optional [craft-fonts](https://github.com/storytold/craft-fonts) input (bundled Japanese
  fonts) is not included; the app falls back to system CJK fonts.
- On Wayland, drag-and-drop and pen-tablet input are unavailable; use the `photocraft-xwayland`
  package (see above).
- Built and used on x86_64-linux. aarch64-linux is listed in the flake but untested.

## License

The packaging files in this repository are licensed under the [MIT License](LICENSE).

PhotoCraft itself is dual-licensed under MIT or Apache-2.0 by its authors. Its ArtCraft name,
wordmark and logos are trademarks of the ArtCraft Team and are covered by upstream's own brand
license. PhotoCraft is not affiliated with Adobe.