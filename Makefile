VERSION := $(shell cat VERSION)

.PHONY: app run install test icon zip clean

## Build build/zzPic.app (universal binary)
app:
	@Scripts/build-app.sh

## Build and launch
run: app
	@open build/zzPic.app

## Copy the app to /Applications
install: app
	@rm -rf /Applications/zzPic.app
	@cp -R build/zzPic.app /Applications/
	@echo "✓ Installed /Applications/zzPic.app"

## Run the unit tests
test:
	@DEVELOPER_DIR=$${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer} swift test

## Redraw the app icon
icon:
	@swift Scripts/make-icon.swift Resources/AppIcon.icns docs/icon.png

## Zip the app for a GitHub release
zip: app
	@cd build && rm -f zzPic-$(VERSION).zip && ditto -c -k --keepParent zzPic.app zzPic-$(VERSION).zip
	@echo "✓ build/zzPic-$(VERSION).zip"

clean:
	@rm -rf .build build
