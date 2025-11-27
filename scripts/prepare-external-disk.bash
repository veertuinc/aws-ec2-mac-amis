#!/bin/bash
set -exo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ../_helpers.bash
if diskutil list /dev/disk4; then
	if ! diskutil list /dev/disk4 | grep -q "Apple_APFS Container"; then
		diskutil eraseDisk APFS "Anka" /dev/disk4
		sudo diskutil enableOwnership /Volumes/Anka
	fi
	diskutil list /dev/disk4
	for username in ec2-user root; do
		[[ "${username}" == "root" ]] && SUDO="sudo" || SUDO=""
		# Always use sudo for mkdir since volume root is owned by root:wheel
		sudo mkdir -p /Volumes/Anka/${username}/img_lib /Volumes/Anka/${username}/state_lib /Volumes/Anka/${username}/vm_lib/.locks
		sudo chown -R ${username} /Volumes/Anka/${username}
		# Run anka config as the target user
		${SUDO} anka config img_lib_dir "/Volumes/Anka/${username}/img_lib"
		${SUDO} anka config state_lib_dir "/Volumes/Anka/${username}/state_lib"
		${SUDO} anka config vm_lib_dir "/Volumes/Anka/${username}/vm_lib"
		${SUDO} anka config vm_lock_dir "/Volumes/Anka/${username}/vm_lib/.locks"
	done
fi
