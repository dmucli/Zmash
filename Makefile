# Zmash — command-line workflow (works from VS Code's terminal).
# Uses the full Xcode toolchain even if xcode-select still points at the Command Line Tools.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

KIT = Packages/ZmashKit
DERIVED = build/DerivedData
APP = $(DERIVED)/Build/Products/Debug-iphoneos/Zmash.app

# The workout catalog (Zwift's and others' content, D166): no build has it unless you ask, with CATALOG=1 on build-sim,
# build-device, build-mac or install, for your own use only. The app tests take it whenever it's been built (make
# workouts), so the check that the library's names are our own runs (D172).
WITH_CATALOG = SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) DEBUG ZMASH_CATALOG' EXCLUDED_SOURCE_FILE_NAMES=
CATALOG_SETTINGS = $(if $(CATALOG),$(WITH_CATALOG))
TEST_CATALOG = $(if $(wildcard Zmash/Resources/Workouts/catalog.json),$(WITH_CATALOG))

.PHONY: test test-app races workouts project build-sim build-device build-mac devices install open clean

## Unit tests for the protocol package (macOS, no simulator or iPad needed)
test:
	cd $(KIT) && swift test

## Unit tests for the app's own logic, in the Simulator: make test-app [SIM="iPhone 17 Pro"]
SIM ?= iPhone 17 Pro
test-app: project
	@# By id: a destination by name assumes the newest iOS, which that Simulator may not run.
	xcodebuild test -project Zmash.xcodeproj -scheme Zmash \
		-destination "platform=iOS Simulator,id=$$(xcrun simctl list devices available | grep -m1 '$(SIM) (' | grep -oE '[0-9A-F-]{36}')" \
		-derivedDataPath $(DERIVED) $(TEST_CATALOG) -quiet

## Rebuild the bundled race catalog from gpx/ (the raw GPX stays on your Mac; only the catalog is committed)
races:
	cd $(KIT) && swift run -c release race-catalog ../../gpx ../../Zmash/Resources/Races/races.json

## Build the workout catalog from the .zwo folders in external sources/ (both stay on this Mac, git-ignored: D169)
WORKOUT_SOURCES = "../../external sources/zwo_workouts" "../../external sources/zwift_workouts-master"
workouts:
	cd $(KIT) && swift run -c release workout-catalog ../../Zmash/Resources/Workouts/catalog.json $(WORKOUT_SOURCES)

## Regenerate Zmash.xcodeproj from project.yml
project:
	xcodegen generate

## Compile the app for the iPad simulator (Bluetooth does not work there; compile check only)
build-sim: project
	xcodebuild -project Zmash.xcodeproj -scheme Zmash -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(DERIVED) $(CATALOG_SETTINGS) build -quiet

## Build a signed app for a real iPad (needs DEVELOPMENT_TEAM set in project.yml)
build-device: project
	xcodebuild -project Zmash.xcodeproj -scheme Zmash -destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates $(CATALOG_SETTINGS) build -quiet

## Build the "Designed for iPad" variant for this Mac (run it from Xcode: destination "My Mac (Designed for iPad)")
build-mac: project
	xcodebuild -project Zmash.xcodeproj -scheme Zmash -destination 'platform=macOS,arch=arm64,variant=Designed for iPad' \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates $(CATALOG_SETTINGS) build -quiet

## List connected devices (to find the iPad's identifier)
devices:
	xcrun devicectl list devices

## Install and launch on the iPad: make install DEVICE=<identifier from `make devices`> [CATALOG=1]
install: build-device
	xcrun devicectl device install app --device $(DEVICE) $(APP)
	xcrun devicectl device process launch --device $(DEVICE) com.davidmucelli.zmash

open: project
	open Zmash.xcodeproj

clean:
	rm -rf build $(KIT)/.build
