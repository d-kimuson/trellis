GHOSTTY_DIR = deps/ghostty
GHOSTTY_INCLUDE = $(GHOSTTY_DIR)/include
GHOSTTY_LIB = $(GHOSTTY_DIR)/zig-out/lib
GHOSTTY_STATIC_LIB = $(GHOSTTY_LIB)/libghostty.a
GHOSTTY_HEADERS = $(GHOSTTY_INCLUDE)
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/OreoreTerminal.app
SWIFT_FILES = $(shell find Sources/OreoreTerminal Sources/OreoreTerminalApp -name '*.swift')

# Ensure Xcode's tools (especially `metal`) are found via /usr/bin/xcrun.
# Nix's stdenv sets DEVELOPER_DIR to its own apple-sdk, which lacks proprietary
# tools like the Metal shader compiler. See flake.nix comments for details.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: all setup build run clean distclean test lint check

all: build

# Clone ghostty source and apply patches for direct macOS static lib build
$(GHOSTTY_DIR):
	@echo "Cloning ghostty..."
	mkdir -p deps
	git clone --depth 1 --branch v1.2.1 https://github.com/ghostty-org/ghostty.git $(GHOSTTY_DIR)
	@echo "Applying patches for macOS static lib build..."
	cd $(GHOSTTY_DIR) && git apply ../../patches/libghostty-macos-static.patch

# Build libghostty as a static lib (bypassing xcframework/iOS)
$(GHOSTTY_STATIC_LIB): $(GHOSTTY_DIR)
	@echo "Building libghostty..."
	cd $(GHOSTTY_DIR) && zig build -Dapp-runtime=none -Demit-xcframework=false -Doptimize=ReleaseFast

setup: $(GHOSTTY_STATIC_LIB)
	@echo "libghostty built successfully!"
	@echo "Headers: $(GHOSTTY_HEADERS)"
	@echo "Library: $(GHOSTTY_STATIC_LIB)"

# Build the app
# Use xcrun to invoke swiftc with the Xcode SDK (not Nix's apple-sdk).
# Nix's apple-sdk has Swift 5.10 interfaces which are incompatible with
# the system Swift 6.x compiler.
SWIFTC = /usr/bin/xcrun -sdk macosx swiftc

$(BUILD_DIR)/OreoreTerminal: $(SWIFT_FILES) $(GHOSTTY_STATIC_LIB)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) \
		-I$(GHOSTTY_HEADERS) \
		-L$(GHOSTTY_LIB) \
		-lghostty \
		-lc++ \
		-framework AppKit \
		-framework SwiftUI \
		-framework Metal \
		-framework MetalKit \
		-framework QuartzCore \
		-framework Carbon \
		-framework CoreText \
		-framework CoreGraphics \
		-framework Foundation \
		-framework IOKit \
		-framework IOSurface \
		-framework UniformTypeIdentifiers \
		-o $(BUILD_DIR)/OreoreTerminal \
		$(SWIFT_FILES)

build: $(BUILD_DIR)/OreoreTerminal
	@echo "Build complete!"

# Create .app bundle
app: $(BUILD_DIR)/OreoreTerminal
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/OreoreTerminal $(APP_BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	@echo "App bundle created: $(APP_BUNDLE)"

run: app
	open $(APP_BUNDLE)

# Testing (via xcodebuild + SPM package)
# Note: `swift test` has a known bug with Xcode 26 testing plugin.
# Using xcodebuild as workaround.
# xcodebuild requires a clean environment — Nix's linker flags break it.
# env -i strips Nix's LD/LDFLAGS contamination.
test: $(GHOSTTY_STATIC_LIB)
	env -i HOME=$(HOME) PATH=/usr/bin:/bin:/usr/sbin DEVELOPER_DIR=$(DEVELOPER_DIR) \
		/usr/bin/xcodebuild test -scheme OreoreTerminal -destination 'platform=macOS' -quiet

# Linting
lint:
	swiftlint lint --quiet Sources/

# Run all checks via check-changed
check:
	npx -y check-changed@0.0.1-beta.4 run

clean:
	rm -rf $(BUILD_DIR)

distclean: clean
	rm -rf deps
