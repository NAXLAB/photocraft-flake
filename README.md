# photocraft-flake

A Nix flake that packages [PhotoCraft](https://github.com/storytold/photocraft), a native,
open-source image editor written in Rust (layers, masks, adjustment layers, PSD support).

The flake tracks upstream's default branch through a flake input. PhotoCraft itself is
developed upstream.

## Usage

Run it without installing:

```sh
nix run github:NAXLAB/photocraft-flake                     # the desktop app
nix run github:NAXLAB/photocraft-flake#photocraft-xwayland # the desktop app, forced to XWayland
nix run github:NAXLAB/photocraft-flake#cli                 # photocraft-cli
```

### Install on NixOS

Add the flake as an input, and make sure your modules receive `inputs` (for example through
`specialArgs = { inherit inputs; };`):

```nix
# flake.nix
inputs.photocraft = {
  url = "github:NAXLAB/photocraft-flake";
  inputs.nixpkgs.follows = "nixpkgs";
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
`xdg-desktop-portal-gtk`) and `hardware.graphics.enable = true` for Vulkan/EGL.

### Drag-and-drop and pen tablets on Wayland

PhotoCraft has no native drag-and-drop on Wayland yet, and its pen-tablet support (pressure and
tilt) is X11-only. The `photocraft-x11` package runs the app under XWayland even in a Wayland
session (it unsets `WAYLAND_DISPLAY`), which enables both:

```nix
environment.systemPackages = [
  inputs.photocraft.packages.${pkgs.stdenv.hostPlatform.system}.photocraft-xwayland
];
```

Or, with the overlay: `pkgs.photocraft.override { x11 = true; }`.

This needs an X server in the session, so `DISPLAY` must be set. Under niri, install
`xwayland-satellite`. XWayland apps can look slightly blurry on HiDPI or fractionally scaled
outputs. On Wayland, File > Open, or pasting an image with Ctrl+V, still works.

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

## Limitations

- The optional [craft-fonts](https://github.com/storytold/craft-fonts) input (bundled Japanese
  fonts) is not included; the app falls back to system CJK fonts.
- On Wayland, drag-and-drop and pen-tablet input are unavailable; use the `photocraft-x11`
  package (see above).
- Built and used on x86_64-linux. aarch64-linux is listed in the flake but untested.

## License

The packaging files in this repository are licensed under the [MIT License](LICENSE).

PhotoCraft itself is dual-licensed under MIT or Apache-2.0 by its authors. Its ArtCraft name,
wordmark and logos are trademarks of the ArtCraft Team and are covered by upstream's own brand
license. PhotoCraft is not affiliated with Adobe.