PREFIX ?= $(HOME)/.local
BIN := .build/release/ps3
XCODE_FLAGS := -project App/PS3Center.xcodeproj -scheme PS3Center -derivedDataPath .build/xcode
APP := .build/xcode/Build/Products/Debug/PS3 Center.app

.PHONY: build test install uninstall project app run-app snapshot snapshot-fixtures

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

# Renders each tab to PNG (needs a reachable console): make snapshot DIR=/tmp/shots
snapshot: app
	PS3CENTER_SNAPSHOT_DIR="$(or $(DIR),$(CURDIR)/.build/snapshots)" "$(APP)/Contents/MacOS/PS3 Center"

# The same without a console, from PS3Kit's Fixtures (what CI renders): make snapshot-fixtures DIR=/tmp/shots
snapshot-fixtures: app
	PS3CENTER_FIXTURES=1 PS3CENTER_SNAPSHOT_DIR="$(or $(DIR),$(CURDIR)/.build/snapshots)" "$(APP)/Contents/MacOS/PS3 Center"
