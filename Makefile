PREFIX ?= $(HOME)/.local
BIN := .build/release/ps3
XCODE_FLAGS := -project App/PS3Center.xcodeproj -scheme PS3Center -derivedDataPath .build/xcode
APP := .build/xcode/Build/Products/Debug/PS3 Center.app
RELEASE_APP := .build/xcode/Build/Products/Release/PS3 Center.app
APPS_DIR ?= /Applications

.PHONY: build test install uninstall project app run-app install-app uninstall-app icon snapshot snapshot-fixtures

build:
	swift build -c release

test:
	swift test

# Symlinks the release binary, so `make build` is enough to update it later.
install: build
	mkdir -p $(PREFIX)/bin
	ln -sf "$(CURDIR)/$(BIN)" $(PREFIX)/bin/ps3
	@echo "Installerat: $(PREFIX)/bin/ps3"

uninstall:
	rm -f $(PREFIX)/bin/ps3

# The Xcode project is generated from App/project.yml and not checked in.
project:
	cd App && xcodegen --quiet

app: project
	xcodebuild $(XCODE_FLAGS) -configuration Debug build

run-app: app
	open "$(APP)"

# A Release build copied to /Applications, so it opens from Launchpad, Spotlight and the Dock like
# any other app. Run it again to update; a running copy is quit first.
install-app: project
	xcodebuild $(XCODE_FLAGS) -configuration Release build
	@if pgrep -xq "PS3 Center"; then osascript -e 'quit app "PS3 Center"'; sleep 2; fi
	rm -rf "$(APPS_DIR)/PS3 Center.app"
	ditto "$(RELEASE_APP)" "$(APPS_DIR)/PS3 Center.app"
	@echo "Installerat: $(APPS_DIR)/PS3 Center.app"

uninstall-app:
	rm -rf "$(APPS_DIR)/PS3 Center.app"

# Renders the app icon again after a change in scripts/make_icon.swift.
icon:
	swift scripts/make_icon.swift App/Sources/Assets.xcassets/AppIcon.appiconset

# Renders each tab to PNG (needs a reachable console): make snapshot DIR=/tmp/shots
snapshot: app
	PS3CENTER_SNAPSHOT_DIR="$(or $(DIR),$(CURDIR)/.build/snapshots)" "$(APP)/Contents/MacOS/PS3 Center"

# The same without a console, from PS3Kit's Fixtures (what CI renders): make snapshot-fixtures DIR=/tmp/shots
snapshot-fixtures: app
	PS3CENTER_FIXTURES=1 PS3CENTER_SNAPSHOT_DIR="$(or $(DIR),$(CURDIR)/.build/snapshots)" "$(APP)/Contents/MacOS/PS3 Center"
