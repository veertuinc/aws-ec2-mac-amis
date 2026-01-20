#!/usr/bin/env bash
set -exo pipefail

# Creates a script that will format the local disk AWS now provides in M4s and mount it as /Volumes/Anka
# Then, it creates the ec2 init file so it runs on boot (useful if you're creating your own AMIs and want it to run on boot)

# if [[ $(sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" 'select count(*) from access where client IN ("com.veertu.anka", "/Library/Application Support/Veertu/Anka/bin/anka_agent", "/Library/Application Support/Veertu/Anka/bin/ankacluster") and auth_value = 2;') -ne 3 ]]; then
# 	echo "ERROR: The following applications must have full disk access for this script to proceed:"
# 	echo "  /Applications/Anka.app"
# 	echo "  /Library/Application Support/Veertu/Anka/bin/anka_agent"
# 	echo "  /Library/Application Support/Veertu/Anka/bin/ankacluster"
# 	exit 1
# fi

[[ ! $EUID -eq 0 ]] && echo "RUN AS ROOT!" && exit 1

cat > /usr/local/bin/prepare-local-disk <<'EOF'
#!/bin/bash
set -eo pipefail

echo "================================"
echo "] Starting prepare-local-disk..."
date
sleep 10
set -x
ls -laht /Volumes/ephemeral0/ || true
ls -laht /Volumes/Anka/ || true
diskutil list

post-run() {
    # safety sleep
    sleep 10

    # disable spotlight indexing on /Volumes/Anka
    mdutil -a -i off /Volumes/Anka || true

    ls -laht /Volumes/ephemeral0/ || true
    ls -laht /Volumes/Anka/ || true

    diskutil list
}
trap post-run EXIT

EXTERNAL_DEVICE="$(/usr/local/libexec/GetInstanceStorageDisk.swift || true)" # always exits 1, even if found

if [[ -z "${EXTERNAL_DEVICE}" || "${EXTERNAL_DEVICE}" != /dev/disk* || ! -e "${EXTERNAL_DEVICE}" ]]; then
    echo "Instance storage disk not found via GetInstanceStorageDisk.swift. Exiting."
    exit 1
fi

# Check for the amazon script that mounts the instance storage disk as /Volumes/ephemeral0
LAUNCHCTL_RESULT=$(launchctl list | grep "com.amazon.ec2.instance-storage-disk-mounter" || true)
if [[ -n "${LAUNCHCTL_RESULT}" ]]; then
    echo "Found amazon script that mounts the instance storage disk as /Volumes/ephemeral0, unloading..."
    launchctl unload -w /Library/LaunchDaemons/com.amazon.ec2.instance-storage-disk-mounter.plist
    echo "Amazon script that mounts the instance storage disk as /Volumes/ephemeral0 unloaded."
else
    echo "Amazon script that mounts the instance storage disk as /Volumes/ephemeral0 not found, nothing to do."
fi

# Check if already mounted as Anka
if mount | grep -q "/Volumes/Anka"; then
    echo "Disk already mounted as /Volumes/Anka, nothing to do"
    exit 1
fi

# Disk exists but not mounted as Anka - erase and format (handles ephemeral0 case)
wait_start=$(date +%s)
while ! mount | grep -q "/Volumes/ephemeral0"; do
    now=$(date +%s)
    if (( now - wait_start >= 160 )); then
        echo "Timeout waiting for /Volumes/ephemeral0; proceeding with erase"
        break
    fi
    echo "Waiting for /Volumes/ephemeral0 to mount before we continue creating /Volumes/Anka..."
    sleep 5
done

apfs_store=$(diskutil list "${EXTERNAL_DEVICE}" | awk '/Apple_APFS/ {print $NF; exit}')
if [[ -n "${apfs_store}" ]]; then
    apfs_container=$(diskutil apfs list | awk -v store="${apfs_store}" '
        /APFS Container Reference:/ {ref=$NF}
        /Physical Store/ && $NF==store {print ref; exit}
    ')
    if [[ -z "${apfs_container}" ]]; then
        echo "Could not find APFS container for ${apfs_store}; refusing to delete."
        exit 1
    fi
    if ! diskutil apfs list "${apfs_container}" | grep -q "ephemeral0"; then
        echo "APFS container is not ephemeral0; refusing to delete. If you're using some sort of special setup for the external disk, this script will not work."
        exit 1
    fi
    diskutil apfs deleteContainer "${apfs_container}" || true
    sudo dd if=/dev/zero of=${EXTERNAL_DEVICE} bs=1m count=10 || true
fi

echo "Formatting disk as Anka..."
diskutil eraseDisk -noEFI APFS "Anka" GPT "${EXTERNAL_DEVICE}"

diskutil list "${EXTERNAL_DEVICE}"
sudo diskutil enableOwnership /Volumes/Anka
for username in root ec2-user; do
    echo "Preparing ${username}..."
    USER_SWITCH=""
    [[ "${username}" != "root" ]] && USER_SWITCH="sudo -u ${username} -H"
    if [[ ! -d /Volumes/Anka/${username}/img_lib || ! -d /Volumes/Anka/${username}/state_lib || ! -d /Volumes/Anka/${username}/vm_lib/.locks ]]; then
        mkdir -p /Volumes/Anka/${username}/img_lib /Volumes/Anka/${username}/state_lib /Volumes/Anka/${username}/vm_lib/.locks
    fi
    chown -R ${username} /Volumes/Anka/${username}
    ${USER_SWITCH} anka config img_lib_dir "/Volumes/Anka/${username}/img_lib" </dev/null
    ${USER_SWITCH} anka config state_lib_dir "/Volumes/Anka/${username}/state_lib" </dev/null
    ${USER_SWITCH} anka config vm_lib_dir "/Volumes/Anka/${username}/vm_lib" </dev/null
    ${USER_SWITCH} anka config vm_lock_dir "/Volumes/Anka/${username}/vm_lib/.locks" </dev/null
done

EOF

chmod +x /usr/local/bin/prepare-local-disk
if /usr/local/bin/prepare-local-disk; then
  cat >> /usr/local/aws/ec2-macos-init/init.toml <<'EOF'

[[Module]]
    Name = "PrepareLocalDisk"
    PriorityGroup = 5
    RunPerBoot = true # Run every boot
    FatalOnError = false # Best effort, don't fatal on error
    [Module.Command]
        Cmd = ["/bin/zsh", "-c", "sudo /usr/local/bin/prepare-local-disk 2>&1 | sudo tee -a /var/log/prepare-local-disk.log"]

EOF
else
  echo "prepare-local-disk failed; not installing init module."
  exit 1
fi