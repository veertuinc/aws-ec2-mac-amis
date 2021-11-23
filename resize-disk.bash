#!/bin/bash
set -exo pipefail
[[ ! $EUID -eq 0 ]] && echo "RUN AS ROOT!" && exit 1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ./_helpers.bash
if [[ ! -e $RESIZE_DISK_PLIST_PATH ]]; then
mkdir -p $LAUNCH_LOCATION
cat > $RESIZE_DISK_PLIST_PATH <<EOD
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>aws-ec2-mac-amis-resize-disk</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/env</string>
		<string>bash</string>
		<string>-c</string>
		<string>/Users/$AWS_INSTANCE_USER/aws-ec2-mac-amis/resize-disk.bash</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>WorkingDirectory</key>
	<string>/Users/$AWS_INSTANCE_USER</string>
	<key>StandardErrorPath</key>
	<string>/var/log/resize-disk.log</string>
	<key>StandardOutPath</key>
	<string>/var/log/resize-disk.log</string>
</dict>
</plist>
EOD
launchctl load -w $RESIZE_DISK_PLIST_PATH
else
  # Modify the disk
  PDISK=$(diskutil list physical external | head -n1 | cut -d" " -f1)
  APFSCONT=$(diskutil list physical external | grep "Apple_APFS" | tr -s " " | cut -d" " -f8)
  echo "y" | diskutil repairDisk $PDISK
  diskutil apfs resizeContainer $APFSCONT 0
fi