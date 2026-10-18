# XM Connect — build with nothing but the Xcode Command Line Tools (xcode-select --install).
#
#   make            build "build/XM Connect.app" for this Mac
#   make run        build and open it
#   make demo       build and open it in demo mode (no headphones needed)
#   make install    copy it to /Applications
#   make pkg        build the installer:  build/XM Connect Installer.pkg  (universal)
#   make dmg        build a disk image:   build/XM Connect.dmg            (universal)
#   make test       run the protocol test suite
#
# Like sony-tray, this drives swiftc directly rather than SwiftPM: a Command-Line-Tools-only Mac
# can have a SwiftPM manifest library that fails to link, while plain swiftc always works.

NAME     := XM Connect
EXE      := XMConnect
BUNDLE_ID := app.xmconnect.mac
VERSION  := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 1.0)

SWIFTC   := swiftc
BUILD    := build
DEPLOY   := 13.0
ARCH     := $(shell uname -m)
APP      := $(BUILD)/$(NAME).app
STAMP    := $(BUILD)/.app-$(if $(filter 1,$(UNIVERSAL)),universal,native)
KIT_SRC  := $(wildcard Sources/SonyProtocolKit/*.swift)
APP_SRC  := $(shell find Sources/XMConnect -name '*.swift')
TEST_SRC := $(wildcard Sources/SonyProtocolTests/*.swift)
FLAGS    := -O
FRAMEWORKS := -framework IOBluetooth -framework AppKit -framework SwiftUI -framework SceneKit \
              -framework Combine -framework ServiceManagement

UNIVERSAL ?= 0
ifeq ($(UNIVERSAL),1)
TARGETS := arm64-apple-macos$(DEPLOY) x86_64-apple-macos$(DEPLOY)
else
TARGETS := $(ARCH)-apple-macos$(DEPLOY)
endif

PREFIX ?= /Applications

# Signing. By default the app is signed ad hoc ("-"). For a release that macOS trusts without
# any warning, set a Developer ID identity (and notarize — see .github/workflows/release.yml):
#   make pkg SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#            INSTALLER_IDENTITY="Developer ID Installer: Name (TEAMID)"
SIGN_IDENTITY ?= -
INSTALLER_IDENTITY ?=
ifeq ($(SIGN_IDENTITY),-)
CODESIGN_FLAGS := --force --sign - --identifier $(BUNDLE_ID)
else
CODESIGN_FLAGS := --force --sign "$(SIGN_IDENTITY)" --identifier $(BUNDLE_ID) --options runtime --timestamp
endif
PRODUCTSIGN := $(if $(INSTALLER_IDENTITY),--sign "$(INSTALLER_IDENTITY)" --timestamp,)

.PHONY: all app run demo install uninstall test universal pkg dmg zip clean

all: app

app: $(STAMP)

$(STAMP): $(KIT_SRC) $(APP_SRC) Resources/Info.plist $(BUILD)/AppIcon.icns
	@rm -rf "$(APP)" $(BUILD)/.app-*
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@for t in $(TARGETS); do \
		echo "  compiling $$t"; \
		d=$(BUILD)/slices/$$t; mkdir -p $$d; \
		$(SWIFTC) $(FLAGS) -target $$t -module-name SonyProtocolKit \
			-emit-module -emit-module-path $$d/SonyProtocolKit.swiftmodule \
			-emit-library -static -o $$d/libSonyProtocolKit.a $(KIT_SRC) || exit 1; \
		$(SWIFTC) $(FLAGS) -target $$t -module-name XMConnect \
			-I $$d -L $$d -lSonyProtocolKit $(FRAMEWORKS) \
			-o $$d/$(EXE) $(APP_SRC) || exit 1; \
	done
	@lipo -create $(foreach t,$(TARGETS),$(BUILD)/slices/$(t)/$(EXE)) -output "$(APP)/Contents/MacOS/$(EXE)"
	@cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	@cp -R Resources/en.lproj Resources/fr.lproj "$(APP)/Contents/Resources/"
	@cp $(BUILD)/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	@printf 'APPL????' > "$(APP)/Contents/PkgInfo"
	@codesign $(CODESIGN_FLAGS) "$(APP)" \
		&& echo "  signed ($(if $(filter -,$(SIGN_IDENTITY)),ad hoc,$(SIGN_IDENTITY)))" \
		|| echo "  warning: signing failed; Bluetooth access may be denied"
	@touch $@
	@echo "built $(APP)"

$(BUILD)/AppIcon.icns: $(wildcard Resources/AppIcon.iconset/*.png)
	@mkdir -p $(BUILD)
	@iconutil -c icns Resources/AppIcon.iconset -o $@

run: app
	@pkill -x $(EXE) 2>/dev/null || true
	@open "$(APP)" --args --open

demo: app
	@pkill -x $(EXE) 2>/dev/null || true
	@open "$(APP)" --args --demo

install: app
	@pkill -x $(EXE) 2>/dev/null || true
	@rm -rf "$(PREFIX)/$(NAME).app"
	@cp -R "$(APP)" "$(PREFIX)/"
	@echo "installed $(PREFIX)/$(NAME).app"

uninstall:
	@pkill -x $(EXE) 2>/dev/null || true
	@rm -rf "$(PREFIX)/$(NAME).app"
	@echo "removed $(PREFIX)/$(NAME).app"

universal:
	@$(MAKE) app UNIVERSAL=1

# --- Installer (.pkg) ------------------------------------------------------------------------
# A standard macOS installer: welcome and conclusion screens in English and French, installs
# into /Applications, quits a running copy first and opens the app when done.
pkg: universal
	@rm -rf $(BUILD)/pkg && mkdir -p $(BUILD)/pkg/root
	@cp -R "$(APP)" $(BUILD)/pkg/root/
	@chmod +x installer/scripts/preinstall installer/scripts/postinstall
	@pkgbuild --analyze --root $(BUILD)/pkg/root $(BUILD)/pkg/component.plist >/dev/null
	@# Always install to /Applications, even if an older copy lives elsewhere.
	@plutil -replace 0.BundleIsRelocatable -bool NO $(BUILD)/pkg/component.plist
	@pkgbuild --root $(BUILD)/pkg/root --component-plist $(BUILD)/pkg/component.plist \
		--install-location /Applications --identifier $(BUNDLE_ID) --version $(VERSION) \
		--scripts installer/scripts $(BUILD)/pkg/XMConnect-component.pkg >/dev/null
	@productbuild --distribution installer/distribution.xml --resources installer/resources \
		--package-path $(BUILD)/pkg $(PRODUCTSIGN) "$(BUILD)/$(NAME) Installer.pkg" >/dev/null
	@echo "built $(BUILD)/$(NAME) Installer.pkg"

# --- Disk image (.dmg) -----------------------------------------------------------------------
dmg: universal
	@rm -rf $(BUILD)/dmg "$(BUILD)/$(NAME).dmg" $(BUILD)/rw.dmg && mkdir -p $(BUILD)/dmg/.background
	@cp -R "$(APP)" $(BUILD)/dmg/
	@ln -s /Applications $(BUILD)/dmg/Applications
	@tiffutil -cathidpicheck installer/dmg-background.png installer/dmg-background@2x.png \
		-out $(BUILD)/dmg/.background/background.tiff 2>/dev/null \
		|| cp installer/dmg-background.png $(BUILD)/dmg/.background/background.tiff
	@hdiutil create -volname "$(NAME)" -srcfolder $(BUILD)/dmg -ov -format UDRW -fs HFS+ $(BUILD)/rw.dmg >/dev/null
	@device=$$(hdiutil attach -readwrite -noverify -noautoopen $(BUILD)/rw.dmg | awk '/Apple_HFS/ {print $$1}'); \
		osascript scripts/dmg-layout.applescript >/dev/null 2>&1 \
			|| echo "  note: window layout skipped (allow Terminal to control Finder for the styled window)"; \
		sync; hdiutil detach $$device -quiet || hdiutil detach $$device -force -quiet
	@hdiutil convert $(BUILD)/rw.dmg -format UDZO -imagekey zlib-level=9 -o "$(BUILD)/$(NAME).dmg" >/dev/null
	@rm -f $(BUILD)/rw.dmg
	@echo "built $(BUILD)/$(NAME).dmg"

# --- Zip (used by the one-line installer) ---------------------------------------------------
zip: universal
	@rm -f $(BUILD)/XM-Connect-macos.zip
	@cd $(BUILD) && ditto -c -k --keepParent --sequesterRsrc "$(NAME).app" XM-Connect-macos.zip
	@echo "built $(BUILD)/XM-Connect-macos.zip"

# --- Tests -----------------------------------------------------------------------------------
test: $(KIT_SRC) $(TEST_SRC)
	@mkdir -p $(BUILD)/test
	@$(SWIFTC) -Onone -target $(ARCH)-apple-macos$(DEPLOY) -module-name SonyProtocolKit \
		-emit-module -emit-module-path $(BUILD)/test/SonyProtocolKit.swiftmodule \
		-emit-library -static -o $(BUILD)/test/libSonyProtocolKit.a $(KIT_SRC)
	@$(SWIFTC) -Onone -target $(ARCH)-apple-macos$(DEPLOY) \
		-I $(BUILD)/test -L $(BUILD)/test -lSonyProtocolKit \
		-o $(BUILD)/test/SonyProtocolTests $(TEST_SRC)
	@$(BUILD)/test/SonyProtocolTests

clean:
	@rm -rf $(BUILD)
	@echo "cleaned"
