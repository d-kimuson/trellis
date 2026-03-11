GHOSTTY_DIR = deps/ghostty
GHOSTTY_INCLUDE = $(GHOSTTY_DIR)/include
GHOSTTY_LIB = $(GHOSTTY_DIR)/zig-out/lib
GHOSTTY_STATIC_LIB = $(GHOSTTY_LIB)/libghostty.a
GHOSTTY_HEADERS = $(GHOSTTY_INCLUDE)
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/Trellis.app
DEBUG_BUNDLE = $(BUILD_DIR)/Trellis-debug.app
DEBUG_LOG_DIR = $(HOME)/Library/Logs/Trellis
SWIFT_FILES = $(shell find Sources/Trellis Sources/TrellisApp -name '*.swift')

.PHONY: all setup build run debug debug-log clean distclean test lint check

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

SWIFTC = xcrun -sdk macosx swiftc

SWIFTC_FLAGS = \
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
	-framework UserNotifications \
	-framework WebKit

$(BUILD_DIR)/Trellis: $(SWIFT_FILES) $(GHOSTTY_STATIC_LIB)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(SWIFTC_FLAGS) -o $(BUILD_DIR)/Trellis $(SWIFT_FILES)

build: $(BUILD_DIR)/Trellis
	@echo "Build complete!"

# Create .app bundle
app: $(BUILD_DIR)/Trellis
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/Trellis $(APP_BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "App bundle created: $(APP_BUNDLE)"

run: app
	open $(APP_BUNDLE)

# Debug build: enables file-based logging (-D DEBUG_LOGGING).
# Logs are written to ~/Library/Logs/Trellis/debug-YYYY-MM-DD-HH-mm-ss.log
$(BUILD_DIR)/Trellis-debug: $(SWIFT_FILES) $(GHOSTTY_STATIC_LIB)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) -D DEBUG_LOGGING $(SWIFTC_FLAGS) -o $(BUILD_DIR)/Trellis-debug $(SWIFT_FILES)

debug-bundle: $(BUILD_DIR)/Trellis-debug
	@mkdir -p $(DEBUG_BUNDLE)/Contents/MacOS
	@mkdir -p $(DEBUG_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/Trellis-debug $(DEBUG_BUNDLE)/Contents/MacOS/Trellis
	cp Resources/Info.plist $(DEBUG_BUNDLE)/Contents/
	cp Resources/AppIcon.icns $(DEBUG_BUNDLE)/Contents/Resources/
	codesign --force --deep --sign - $(DEBUG_BUNDLE)

debug: debug-bundle
	@mkdir -p $(DEBUG_LOG_DIR)
	@echo ""
	@echo "  Trellis debug mode"
	@echo "  Logs → $(DEBUG_LOG_DIR)/debug-*.log"
	@echo "  Run 'make debug-log' in another terminal to tail the latest log."
	@echo ""
	open $(DEBUG_BUNDLE)

# Tail the most recent debug log file.
debug-log:
	@latest=$$(ls -t $(DEBUG_LOG_DIR)/debug-*.log 2>/dev/null | head -1); \
	if [ -z "$$latest" ]; then \
		echo "No debug logs found in $(DEBUG_LOG_DIR). Run 'make debug' first."; \
	else \
		echo "Tailing: $$latest"; \
		tail -f "$$latest"; \
	fi

# Testing (via xcodebuild + SPM package)
# Note: `swift test` has a known bug with Xcode 26 testing plugin.
# env -i: xcodebuild needs a clean environment (Nix sets vars like
# NIX_ENFORCE_NO_NATIVE that break the linker).
test: $(GHOSTTY_STATIC_LIB)
	env -i HOME=$(HOME) PATH=$(PATH) \
		xcodebuild test -scheme Trellis -destination 'platform=macOS' -quiet

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
