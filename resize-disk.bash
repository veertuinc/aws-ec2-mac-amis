#!/bin/bash
set -exo pipefail
[[ ! $EUID -eq 0 ]] && echo "RUN AS ROOT!" && exit 1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
echo "$(date) Resizing disk..."
cd $SCRIPT_DIR
. ./_helpers.bash
fin() {
  echo "finished" > /tmp/resize-disk.status
}
trap fin EXIT
echo "running" > /tmp/resize-disk.status
if [[ ! -e "${RESIZE_DISK_PLIST_PATH}" ]]; then
cat > "${RESIZE_DISK_PLIST_PATH}" <<EOD
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
		<string>/Users/${AWS_INSTANCE_USER:-"ec2-user"}/aws-ec2-mac-amis/resize-disk.bash</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>WorkingDirectory</key>
	<string>/Users/${AWS_INSTANCE_USER:-"ec2-user"}</string>
	<key>StandardErrorPath</key>
	<string>/var/log/resize-disk.log</string>
	<key>StandardOutPath</key>
	<string>/var/log/resize-disk.log</string>
</dict>
</plist>
EOD
launchctl load -w "${RESIZE_DISK_PLIST_PATH}"
else
	# Looks like AWS provides a resize tool now.
	ec2-macos-utils grow --id root --verbose
#   # Modify the disk
#   PDISK=$(
#     diskutil list physical external | awk '/^\/dev\/disk/ {print $1}' | while read -r disk; do
#       if diskutil list "${disk}" | awk '$2=="EFI" {found=1} END {exit found ? 0 : 1}'; then
#         echo "${disk}"
#         break
#       fi
#     done
#   )
#   APFSCONT=$(diskutil list "${PDISK}" | awk '/Apple_APFS/ {print $NF; exit}')
#   echo "y" | diskutil repairDisk $PDISK
#   diskutil apfs resizeContainer $APFSCONT 0
fi