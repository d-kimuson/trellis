{
  description = "oreore-terminal - A tmux alternative built on libghostty";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "aarch64-darwin" "x86_64-darwin" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Zig 0.14 for building libghostty (ghostty 1.2.x)
            zig_0_14
            # Build tools
            gnumake
            pkg-config
            # For ghostty build dependencies
            freetype
            fontconfig
            libxml2
          ];

          # Prerequisites (not manageable via Nix):
          #   - Xcode: Required for Apple's proprietary `metal` shader compiler.
          #     libghostty uses Metal for GPU-accelerated terminal rendering on macOS,
          #     and its build compiles .metal shaders into .metallib via `xcrun metal`.
          #     `metal` is bundled exclusively in Xcode.app (not in CommandLineTools).
          #     Ensure xcode-select points to Xcode:
          #       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

          shellHook = ''
            # Override DEVELOPER_DIR so that `/usr/bin/xcrun` resolves tools (especially
            # `metal`) from the real Xcode installation instead of Nix's apple-sdk shim.
            export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

            echo "oreore-terminal dev shell"
            echo "  zig: $(zig version)"
            echo ""

            # Verify xcode-select points to Xcode (not CommandLineTools)
            if ! /usr/bin/xcrun -sdk macosx -f metal &>/dev/null; then
              echo "WARNING: 'metal' compiler not found."
              echo "  libghostty requires Xcode's Metal shader compiler (proprietary, not in nixpkgs)."
              echo "  Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
              echo ""
            fi

            echo "Steps:"
            echo "  1. make setup    - Clone ghostty and build libghostty"
            echo "  2. make build    - Build oreore-terminal"
            echo "  3. make run      - Run the app"
          '';
        };
      }
    );
}
