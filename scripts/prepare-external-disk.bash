#!/bin/bash
set -exo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ../_helpers.bash
if diskutil list /dev/disk4; then
	# Get the APFS container reference
	APFS_CONTAINER=$(diskutil list /dev/disk4 | grep "Apple_APFS Container" | awk '{print $NF}' | sed 's/s[0-9]*$//')
	
	if [[ -z "$APFS_CONTAINER" ]]; then
		# No APFS container yet, create one
		diskutil eraseDisk APFS "Anka" /dev/disk4
		APFS_CONTAINER=$(diskutil list /dev/disk4 | grep "Apple_APFS Container" | awk '{print $NF}' | sed 's/s[0-9]*$//')
	fi
	
	diskutil list /dev/disk4
	
	for username in ec2-user root; do
		[[ "${username}" == "root" ]] && SUDO="sudo" || SUDO=""
		VOLUME_NAME="Anka-${username}"
		
		# Create a separate APFS volume for each user if it doesn't exist
		if ! diskutil list "$APFS_CONTAINER" | grep -q "$VOLUME_NAME"; then
			diskutil apfs addVolume "$APFS_CONTAINER" APFS "$VOLUME_NAME" -nomount
			diskutil mount "$VOLUME_NAME"
			diskutil enableOwnership "/Volumes/${VOLUME_NAME}"
		fi
		
		# Ensure volume is mounted
		[[ ! -d "/Volumes/${VOLUME_NAME}" ]] && diskutil mount "$VOLUME_NAME"
		
		# Create subdirectories and set ownership
		sudo mkdir -p "/Volumes/${VOLUME_NAME}/img_lib" "/Volumes/${VOLUME_NAME}/state_lib" "/Volumes/${VOLUME_NAME}/vm_lib/.locks"
		sudo chown -R ${username} "/Volumes/${VOLUME_NAME}"
		
		# Run anka config as the target user
		${SUDO} anka config img_lib_dir "/Volumes/${VOLUME_NAME}/img_lib"
		${SUDO} anka config state_lib_dir "/Volumes/${VOLUME_NAME}/state_lib"
		${SUDO} anka config vm_lib_dir "/Volumes/${VOLUME_NAME}/vm_lib"
		${SUDO} anka config vm_lock_dir "/Volumes/${VOLUME_NAME}/vm_lib/.locks"
	done
fi
