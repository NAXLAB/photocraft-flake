{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  nasm,
  libxkbcommon,
  wayland,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  vulkan-loader,
  libGL,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "photocraft";
  # Workspace version from Cargo.toml; upstream publishes no tags on this repo, so the
  # pinned commit date is appended.
  version = "0.2.0-unstable-2026-10-06";

  src = fetchFromGitHub {
    owner = "openhausfun";
    repo = "photocraft";
    rev = "67808f5abb3ce1a71b10d04b889c6eac4db43ba7";
    hash = "sha256-4uIESy5QkwPIzuXHT0mifLuvCDz4dKGyUIsT58WCRSE=";
  };

  # Every dependency in Cargo.lock comes from crates.io (no git sources), so no
  # outputHashes are needed. Reading the lockfile out of `src` is import-from-derivation;
  # swap this for `cargoHash = "...";` if you ever want to upstream the package to nixpkgs.
  cargoLock.lockFile = "${finalAttrs.src}/Cargo.lock";

  # The workspace has 24 crates plus xtask and a wasm app; build only the two binaries
  # upstream ships on Linux (see packaging/linux/package.sh).
  cargoBuildFlags = [
    "--package"
    "photocraft"
    "--package"
    "photocraft-cli"
  ];

  nativeBuildInputs = [
    pkg-config
  ]
  # rav1e (AVIF encoding) uses nasm for its x86_64 assembly kernels.
  ++ lib.optionals stdenv.hostPlatform.isx86_64 [ nasm ];

  # winit, wgpu and arboard load these with dlopen at runtime, so they are not ELF NEEDED
  # entries. Upstream's own list is in packaging/linux/nfpm.yaml. They live in buildInputs
  # so the dev shell can reuse them, and are added to the RPATH in postFixup.
  buildInputs = [
    libxkbcommon # also provides libxkbcommon-x11
    wayland
    libx11
    libxcb
    libxcursor
    libxi
    vulkan-loader
    libGL # libEGL fallback when Vulkan is unavailable
  ];

  # The test suite includes GPU/UI snapshot tests (egui_kittest) and corpus tests that
  # download PSD files, none of which work in the sandbox.
  doCheck = false;

postInstall = ''
  install -Dm644 packaging/linux/ai.storyteller.photocraft.desktop \
    $out/share/applications/ai.storyteller.photocraft.desktop
  install -Dm644 packaging/linux/ai.storyteller.photocraft.mime.xml \
    $out/share/mime/packages/ai.storyteller.photocraft.xml

  mkdir -p $out/share/metainfo
  substitute packaging/linux/ai.storyteller.photocraft.metainfo.xml.in \
    $out/share/metainfo/ai.storyteller.photocraft.metainfo.xml \
    --subst-var-by VERSION "${lib.head (lib.splitString "-" finalAttrs.version)}" \
    --subst-var-by DATE "2026-10-06"

  mkdir -p $out/share/icons
  cp -r assets/app-icon/hicolor $out/share/icons/
'';


  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf --add-rpath ${lib.makeLibraryPath finalAttrs.buildInputs} $out/bin/photocraft
  '';

  meta = {
    description = "Native, open-source image editor with layers, masks and PSD support, written in Rust";
    homepage = "https://github.com/openhausfun/photocraft";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "photocraft";
    platforms = lib.platforms.linux;
  };
})
