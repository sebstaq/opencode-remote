SHELL := /bin/bash
SIM_NAME := iPhone 17
DESTINATION := platform=iOS Simulator,name=$(SIM_NAME)

.PHONY: generate prepare-sim format lint build test e2e measure

generate:
	xcodegen generate

# iOS 26 simulators need accessibility enabled for XCUITest; see the script.
prepare-sim:
	scripts/prepare-sim.sh '$(SIM_NAME)'

format:
	swift format --in-place --recursive App Tests Packages/OpenCodeAPI/Package.swift

lint:
	swift format lint --strict --recursive App Tests Packages/OpenCodeAPI/Package.swift
	swift build --package-path Packages/OpenCodeAPI

build: generate
	xcodebuild -project OpenCodeRemote.xcodeproj -scheme OpenCodeRemote -destination '$(DESTINATION)' -skipPackagePluginValidation build

test: generate
	xcodebuild test -project OpenCodeRemote.xcodeproj -scheme OpenCodeRemote -destination '$(DESTINATION)' -skipPackagePluginValidation -skip-testing:OpenCodeRemoteUITests

e2e: generate
	scripts/ui-tests.sh '$(SIM_NAME)' -only-testing:OpenCodeRemoteUITests

measure:
	scripts/measure.sh
