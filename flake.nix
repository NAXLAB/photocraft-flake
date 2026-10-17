{
  description = "PhotoCraft: a native, open-source image editor written in Rust";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Upstream source. `flake = false` because the repo has no flake.nix of its own.
    # Pinned in flake.lock; `nix flake update photocraft-src` moves it to the latest commit.
    photocraft-src = {
      url = "github:storytold/photocraft";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      photocraft-src,
    }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});

      # The package definition (formerly package.nix), called via callPackage below.
      package =
        {
          lib,
          stdenv,
          rustPlatform,
          pkg-config,
          makeWrapper,
          nasm,
          libxkbcommon,
          wayland,
          libx11,
          libxcb,
          libxcursor,
          libxi,
          vulkan-loader,
          libGL,
          dbus,
          # Run under XWayland even in a Wayland session. PhotoCraft has no native drag-and-drop on
          # Wayland yet, and its pen-tablet support (pressure/tilt) is X11-only. Needs an X server in the
          # session (DISPLAY set), e.g. xwayland-satellite under niri.
          x11 ? false,
          # The upstream source tree (the `photocraft-src` input).
          src,
        }:

        let
          # Everything below is derived from the source, so updating the flake input needs no edits here.
          workspaceVersion =
            (builtins.fromTOML (builtins.readFile "${src}/Cargo.toml")).workspace.package.version;
          # Flake inputs expose lastModifiedDate as YYYYMMDDHHMMSS.
          d = src.lastModifiedDate or "19700101000000";
          date = "${builtins.substring 0 4 d}-${builtins.substring 4 2 d}-${builtins.substring 6 2 d}";
        in
        rustPlatform.buildRustPackage (finalAttrs: {
          pname = "photocraft";
          # The flake input follows upstream's default branch, so the commit date marks the snapshot.
          version = "${workspaceVersion}-unstable-${date}";

          inherit src;

          cargoLock = {
            lockFile = "${src}/Cargo.lock";
            allowBuiltinFetchGit = true;
          };

          # The workspace has many crates plus xtask and a wasm app; build only the two binaries
          # upstream ships on Linux, with the same flags as its official builds
          # (see packaging/linux/package.sh). `heif` enables HEIC/HEIF decoding, which is pure Rust.
          cargoBuildFlags = [
            "--package"
            "photocraft"
            "--package"
            "photocraft-cli"
            "--features"
            "heif"
          ];

          nativeBuildInputs = [
            pkg-config
            makeWrapper
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
            # rfd's xdg-portal backend dlopens libdbus-1.so.3 to talk to xdg-desktop-portal. If it
            # isn't found, every Open/Save/Export dialog silently fails to appear.
            dbus
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
              --subst-var-by VERSION "${workspaceVersion}" \
              --subst-var-by DATE "${date}"
            mkdir -p $out/share/icons
            cp -r assets/app-icon/hicolor $out/share/icons/
          '';

          postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
            patchelf --add-rpath ${lib.makeLibraryPath finalAttrs.buildInputs} $out/bin/photocraft

            # The app's start-up check looks for its runtime libraries via ldconfig and LD_LIBRARY_PATH,
            # neither of which exists on NixOS (the libraries are in the RPATH), so it prints a false
            # "could not find these libraries" warning. Skip it rather than leak LD_LIBRARY_PATH into
            # child processes.
            wrapProgram $out/bin/photocraft \
              --set PHOTOCRAFT_SKIP_LIB_CHECK 1${lib.optionalString x11 " \\\n      --unset WAYLAND_DISPLAY"}
          '';

          meta = {
            description = "Native, open-source image editor with layers, masks and PSD support, written in Rust";
            homepage = "https://github.com/storytold/photocraft";
            license = with lib.licenses; [
              mit
              asl20
            ];
            mainProgram = "photocraft";
            platforms = lib.platforms.linux;
          };
        });

      mkPackage = pkgs: pkgs.callPackage package { src = photocraft-src; };
    in
    {
      packages = forAllSystems (
        _system: pkgs: rec {
          photocraft = mkPackage pkgs;
          # Forces XWayland: enables drag-and-drop and pen-tablet input on Wayland sessions.
          photocraft-xwayland = photocraft.override { x11 = true; };
          default = photocraft;
        }
      );

      apps = forAllSystems (
        system: _pkgs: {
          default = {
            type = "app";
            program = lib.getExe self.packages.${system}.photocraft;
          };
          cli = {
            type = "app";
            program = "${self.packages.${system}.photocraft}/bin/photocraft-cli";
          };
        }
      );

      devShells = forAllSystems (
        system: pkgs: {
          default = pkgs.mkShell {
            inputsFrom = [ self.packages.${system}.photocraft ];
            packages = with pkgs; [
              rust-analyzer
              clippy
              rustfmt
            ];
            # Lets `cargo run -p photocraft` find the dlopen'd windowing/GPU libraries.
            LD_LIBRARY_PATH = lib.makeLibraryPath self.packages.${system}.photocraft.buildInputs;
          };
        }
      );

      # For `nixpkgs.overlays = [ photocraft.overlays.default ];`, giving `pkgs.photocraft`.
      overlays.default = final: _prev: {
        photocraft = mkPackage final;
      };
    };
}