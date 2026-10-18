-- Arranges the disk image window: background, icon positions, no toolbar.
-- Run by `make dmg` while the read-write image is mounted. Failure is harmless.
tell application "Finder"
	tell disk "XM Connect"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set the bounds of container window to {200, 120, 860, 548}
		set viewOptions to the icon view options of container window
		set arrangement of viewOptions to not arranged
		set icon size of viewOptions to 128
		set text size of viewOptions to 13
		set background picture of viewOptions to file ".background:background.tiff"
		set position of item "XM Connect.app" of container window to {170, 190}
		set position of item "Applications" of container window to {490, 190}
		close
		open
		update without registering applications
		delay 1
		close
	end tell
end tell
