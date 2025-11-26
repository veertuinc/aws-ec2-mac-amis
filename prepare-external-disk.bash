#!/bin/bash
set -exo pipefail
[[ ! $EUID -eq 0 ]] && echo "RUN AS ROOT!" && exit 1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ./_helpers.bash

fin() {
  echo "finished" > /tmp/prepare-external-disk.status
}
trap fin EXIT
echo "running" > /tmp/prepare-external-disk.status

EXTERNAL_DISK_PLIST_PATH="${LAUNCH_LOCATION}com.veertu.aws-ec2-mac-amis.prepare-external-disk.plist"

if [[ ! -e "${EXTERNAL_DISK_PLIST_PATH}" ]]; then
cat > "${EXTERNAL_DISK_PLIST_PATH}" <<EOD
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>aws-ec2-mac-amis-prepare-external-disk</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/env</string>
		<string>bash</string>
		<string>-c</string>
		<string>/Users/${AWS_INSTANCE_USER:-"ec2-user"}/aws-ec2-mac-amis/prepare-external-disk.bash</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>WorkingDirectory</key>
	<string>/Users/${AWS_INSTANCE_USER:-"ec2-user"}</string>
	<key>StandardErrorPath</key>
	<string>/var/log/prepare-external-disk.log</string>
	<key>StandardOutPath</key>
	<string>/var/log/prepare-external-disk.log</string>
</dict>
</plist>
EOD
launchctl load -w "${EXTERNAL_DISK_PLIST_PATH}"
else
	whoami
  # Only run on M4 Macs with external disk
	if diskutil list /dev/disk4; then
		if ! diskutil list /dev/disk4 | grep -q disk4s1; then
			diskutil eraseDisk APFS "Anka" /dev/disk4
		fi
		diskutil list /dev/disk4
		for username in root ec2-user; do
			mkdir -p /Volumes/Anka/${username}/img_lib /Volumes/Anka/${username}/state_lib /Volumes/Anka/${username}/vm_lib/.locks
			chown -R ${username} /Volumes/Anka/${username}
			if [[ "${username}" == "root" ]]; then
				anka config img_lib_dir "/Volumes/Anka/${username}/img_lib"
				anka config state_lib_dir "/Volumes/Anka/${username}/state_lib"
				anka config vm_lib_dir "/Volumes/Anka/${username}/vm_lib"
				anka config vm_lock_dir "/Volumes/Anka/${username}/vm_lib/.locks"
			else
				sudo -ui ${username} anka config img_lib_dir "/Volumes/Anka/${username}/img_lib"
				sudo -ui ${username} anka config state_lib_dir "/Volumes/Anka/${username}/state_lib"
				sudo -ui ${username} anka config vm_lib_dir "/Volumes/Anka/${username}/vm_lib"
				sudo -ui ${username} anka config vm_lock_dir "/Volumes/Anka/${username}/vm_lib/.locks"
			fi
		done
	fi
fi
