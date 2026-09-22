# Zmash — command-line workflow (works from VS Code's terminal).
# Uses the full Xcode toolchain even if xcode-select still points at the Command Line Tools.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

KIT = Packages/ZmashKit
DERIVED = build/DerivedData
APP = $(DERIVED)/Build/Products/Debug-iphoneos/Zmash.app

.PHONY: test project build-sim build-device build-mac devices install open clean

## Unit tests for the protocol package (macOS, no simulator or iPad needed)
test:
	cd $(KIT) && swift test

## Regenerate Zmash.xcodeproj from project.yml
project:
	xcodegen generate

## Compile the app for the iPad simulator (Bluetooth does not work there; compile check only)
build-sim: project
	xcodebuild -project Zmash.xcodeproj -scheme Zmash -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(DERIVED) build -quiet

## Build a signed app for a real iPad (needs DEVELOPMENT_TEAM set in project.yml)
build-device: project
	xcodebuild -project Zmash.xcodeproj -scheme Zmash -destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates build -quiet

## Build the "Designed for iPad" variant for this Mac (run it from Xcode: destination "My Mac (Designed for iPad)")
build-mac: project
	xcodebuild -project Zmash.xcodeproj -scheme Zmash -destination 'platform=macOS,arch=arm64,variant=Designed for iPad' \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates build -quiet

## List connected devices (to find the iPad's identifier)
devices:
	xcrun devicectl list devices

## Install and launch on the iPad: make install DEVICE=<identifier from `make devices`>
install: build-device
	xcrun devicectl device install app --device $(DEVICE) $(APP)
	xcrun devicectl device process launch --device $(DEVICE) com.davidmucelli.zmash

open: project
	open Zmash.xcodeproj

clean:
	rm -rf build $(KIT)/.build
