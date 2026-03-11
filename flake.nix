{
  description = "Trellis - Terminal app built on libghostty";

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
        # mkShellNoCC: provides tools in PATH without pulling in the C
        # toolchain (apple-sdk/clang). This avoids LDFLAGS/CFLAGS/DEVELOPER_DIR
        # contamination that conflicts with Xcode's native toolchain.
        devShells.default = pkgs.mkShellNoCC {
          buildInputs = with pkgs; [
            zig_0_14    # Building libghostty (ghostty 1.2.x)
            gnumake
            pkg-config
            swiftlint
          ];

          # Prerequisite: Xcode (for `metal` shader compiler, `swiftc`, `xcodebuild`)
          #   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

          shellHook = ''
            # Remove Nix's xcbuild from PATH — it shadows /usr/bin/xcrun,
            # xcodebuild, etc. and can't find the macOS SDK.
            export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v xcbuild | tr '\n' ':')

            echo "trellis dev shell"
            echo "  zig: $(zig version)"
            echo ""

            if ! xcrun -sdk macosx -f metal &>/dev/null; then
              echo "WARNING: 'metal' compiler not found."
              echo "  Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
              echo ""
            fi
          '';
        };
      }
    );
}
