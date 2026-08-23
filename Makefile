SHELL := /bin/bash
DERIVED_DATA ?= $(CURDIR)/.build/Xcode
DESTINATION ?= platform=macOS,arch=arm64
XCODEBUILD := xcodebuild -project Watchio.xcodeproj -scheme Watchio -destination '$(DESTINATION)' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO
SWIFT_SOURCES := WatchioApp WatchioWidget WatchioUITests Packages/WatchioCore/Sources Packages/WatchioCore/Tests

.PHONY: format format-check test ui-test build release-build coverage privacy-check docs-check check

format:
	xcrun swift-format format --in-place --recursive $(SWIFT_SOURCES)

format-check:
	xcrun swift-format lint --strict --recursive $(SWIFT_SOURCES)

test:
	swift test --package-path Packages/WatchioCore

ui-test:
	xcodebuild -quiet -project Watchio.xcodeproj -scheme Watchio -destination '$(DESTINATION)' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGN_IDENTITY=- test

build:
	$(XCODEBUILD) -configuration Debug build

release-build:
	$(XCODEBUILD) -configuration Release ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build

coverage:
	./Scripts/coverage.sh

privacy-check:
	./Scripts/check-privacy-invariants.sh

docs-check:
	ruby Scripts/check-doc-links.rb

check: format-check test privacy-check docs-check build
