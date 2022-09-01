#!/bin/bash
set -exo pipefail
unset HISTFILE
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ../_helpers.bash
# Perform changes that all macOS versions support + install anka virtualization
. ../_common-prep.bash
[[ ! -e $RESIZE_DISK_PLIST_PATH ]] && sudo -E bash -c "pwd; ../resize-disk.bash"
# Create plist for cloud connect # Should be last!
[[ ! -e $CLOUD_CONNECT_PLIST_PATH ]] && sudo -E bash -c "../cloud-connect.bash"
sudo chown -R $AWS_INSTANCE_USER:staff ~/aws-ec2-mac-amis
# sudo anka config vmx_mitigations 0 # Apple has locked this and it can no longer be modified
# [[ -z "$(sudo sysadminctl -secureTokenStatus ec2-user 2>&1 | grep ENABLED)" ]] && sudo /usr/bin/dscl . -passwd /Users/ec2-user "${AWS_INSTANCE_USER_PASSWD}" # We don't need this since VNC is now disabled by default
echo ""
echo "]] SUCCESS"
unset HISTFILE