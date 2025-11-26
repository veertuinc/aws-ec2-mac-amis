#!/bin/bash
set -exo pipefail
[[ ! $EUID -eq 0 ]] && echo "RUN AS ROOT!" && exit 1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ./_helpers.bash

if diskutil list /dev/disk4; then
	if ! diskutil list /dev/disk4 | grep -q disk4s1; then
		diskutil eraseDisk APFS "Anka" /dev/disk4
	fi
	diskutil list /dev/disk4
	for username in root ec2-user; do
		mkdir -p /Volumes/Anka/${username}/img_lib /Volumes/Anka/${username}/state_lib /Volumes/Anka/${username}/vm_lib/.locks
		if [[ "${username}" == "root" ]]; then
			sudo chown -R ${username} /Volumes/Anka/${username}
			sudo anka config img_lib_dir "/Volumes/Anka/${username}/img_lib"
			sudo anka config state_lib_dir "/Volumes/Anka/${username}/state_lib"
			sudo anka config vm_lib_dir "/Volumes/Anka/${username}/vm_lib"
			sudo anka config vm_lock_dir "/Volumes/Anka/${username}/vm_lib/.locks"
		else
			chown -R ${username} /Volumes/Anka/${username}
			anka config img_lib_dir "/Volumes/Anka/${username}/img_lib"
			anka config state_lib_dir "/Volumes/Anka/${username}/state_lib"
			anka config vm_lib_dir "/Volumes/Anka/${username}/vm_lib"
			anka config vm_lock_dir "/Volumes/Anka/${username}/vm_lib/.locks"
		fi
	done
fi
