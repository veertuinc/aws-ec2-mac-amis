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
		[[ "${username}" == "root" ]] && SUDO="sudo" || SUDO=""
		${SUDO} mkdir -p /Volumes/Anka/${username}/img_lib /Volumes/Anka/${username}/state_lib /Volumes/Anka/${username}/vm_lib/.locks
		${SUDO} chown -R ${username} /Volumes/Anka/${username}
		${SUDO} anka config img_lib_dir "/Volumes/Anka/${username}/img_lib"
		${SUDO} anka config state_lib_dir "/Volumes/Anka/${username}/state_lib"
		${SUDO} anka config vm_lib_dir "/Volumes/Anka/${username}/vm_lib"
		${SUDO} anka config vm_lock_dir "/Volumes/Anka/${username}/vm_lib/.locks"
	done
fi
