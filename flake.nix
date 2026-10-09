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
    { self, nixpkgs, photocraft-src }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
      mkPackage = pkgs: pkgs.callPackage ./package.nix { src = photocraft-src; };
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