#!/bin/bash
set -exo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ../_helpers.bash
# Perform changes that all macOS versions support + install anka virtualization
. ../_common-prep.bash
# Create plist for cloud connect
[[ ! -e $CLOUD_CONNECT_PLIST_PATH ]] && sudo -E bash -c "../cloud-connect.bash"
[[ ! -e $RESIZE_DISK_PLIST_PATH ]] && sudo -E bash -c "../resize-disk.bash"