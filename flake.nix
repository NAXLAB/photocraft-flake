{
  description = "PhotoCraft: a native, open-source image editor written in Rust";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (
        _system: pkgs: rec {
          photocraft = pkgs.callPackage ./package.nix { };
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

      # For `nixpkgs.overlays = [ photocraft.overlays.default ];` in a NixOS or
      # home-manager configuration, giving `pkgs.photocraft`.
      overlays.default = final: _prev: {
        photocraft = final.callPackage ./package.nix { };
      };
    };
}
