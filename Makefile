# Command Line Tools ship Swift Testing outside the default plugin path; Xcode (and CI) does not need the flag.
TESTING_PLUGIN_PATH := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
ifneq (,$(findstring CommandLineTools,$(shell xcode-select -p)))
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGIN_PATH)
endif

.PHONY: build test lint release

build:
	swift build

test:
	swift test $(TEST_FLAGS)

lint:
	swift format lint --strict -r Sources Tests Package.swift

release:
	swift build -c release --arch arm64 --arch x86_64
