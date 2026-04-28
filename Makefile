# Mac Vulture — dev workflow
#
# Common:
#   make            # build + run
#   make test       # swift test
#   make icons      # regen AppIcon PNGs from icon.svg
#   make clean      # nuke build dir
#   make release    # release .app + DMG (needs Developer ID env)

PROJECT      := MacVulture.xcodeproj
SCHEME       := MacVulture
CONFIG_DEBUG := Debug
CONFIG_REL   := Release
DD           := build/dd
APP_DEBUG    := $(DD)/Build/Products/$(CONFIG_DEBUG)/Mac Vulture.app
APP_REL      := $(DD)/Build/Products/$(CONFIG_REL)/Mac Vulture.app

XCODEGEN := $(shell command -v xcodegen 2>/dev/null)

.PHONY: all run build test clean rebuild regen icons release notarize fmt help \
        kill open dock-flush install-tools

all: run

help:
	@echo "Targets:"
	@echo "  make / make run  - build + launch app"
	@echo "  make build       - debug build"
	@echo "  make test        - swift test"
	@echo "  make rebuild     - clean + build"
	@echo "  make regen       - run xcodegen"
	@echo "  make icons       - regen AppIcon PNGs"
	@echo "  make clean       - rm build/"
	@echo "  make kill        - quit running Mac Vulture"
	@echo "  make dock-flush  - killall Dock (refresh icon cache)"
	@echo "  make release     - release build + DMG (needs Developer ID env)"
	@echo "  make install-tools - brew install xcodegen"

regen:
ifndef XCODEGEN
	@echo "xcodegen missing. Run: make install-tools"
	@exit 1
endif
	@xcodegen --quiet

build: regen
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG_DEBUG) \
		-derivedDataPath $(DD) build -quiet

run: kill build
	@open "$(APP_DEBUG)"

test:
	@swift test --parallel

clean:
	@rm -rf build .build .swiftpm

rebuild: clean build

kill:
	-@pkill -x "Mac Vulture" 2>/dev/null || true

dock-flush: kill
	-@killall Dock 2>/dev/null || true

icons:
	@./packaging/scripts/make-appicon.sh icon.svg App/Assets.xcassets/AppIcon.appiconset

release: regen
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG_REL) \
		-derivedDataPath $(DD) build
	@mkdir -p build
	@cp -R "$(APP_REL)" build/
	@./packaging/notarize.sh

notarize:
	@./packaging/notarize.sh

install-tools:
	@command -v xcodegen >/dev/null || brew install xcodegen
	@command -v xcbeautify >/dev/null || brew install xcbeautify
