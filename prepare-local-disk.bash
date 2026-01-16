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
set -exo pipefail

diskutil list

EXTERNAL_DEVICE=$(
    diskutil list physical external | awk '/^\/dev\/disk/ {print $1}' | while read -r disk; do
        apfs_store=$(diskutil list "${disk}" | awk '/Apple_APFS/ {print $NF; exit}')
        if [[ -n "${apfs_store}" ]]; then
            apfs_container=$(diskutil apfs list | awk -v store="${apfs_store}" '
                /APFS Container Reference:/ {ref=$NF}
                /Physical Store/ && $NF==store {print ref; exit}
            ')
            if [[ -n "${apfs_container}" ]]; then
                if diskutil apfs list "${apfs_container}" | grep -q "Macintosh HD"; then
                    continue
                fi
            fi
        fi
        echo "${disk}"
        break
    done
)

if [[ -z "${EXTERNAL_DEVICE}" || ! -e "${EXTERNAL_DEVICE}" ]]; then
    echo "External non-EFI disk not found. Exiting."
    exit 1
fi

# Check if already mounted as Anka
if mount | grep -q "/Volumes/Anka"; then
    echo "Disk already mounted as /Volumes/Anka, nothing to do"
    exit 0
fi

# Disk exists but not mounted as Anka - erase and format (handles ephemeral0 case)
wait_start=$(date +%s)
while ! mount | grep -q "/Volumes/ephemeral0"; do
    now=$(date +%s)
    if (( now - wait_start >= 300 )); then
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
fi

echo "Formatting disk as Anka..."
diskutil eraseDisk APFS "Anka" "${EXTERNAL_DEVICE}"

diskutil list "${EXTERNAL_DEVICE}"
for username in root ec2-user; do
    echo "Preparing ${username}..."
    [[ "${username}" != "root" ]] && USER_SWITCH="sudo -u ${username}"
    if [[ ! -d /Volumes/Anka/${username}/img_lib || ! -d /Volumes/Anka/${username}/state_lib || ! -d /Volumes/Anka/${username}/vm_lib/.locks ]]; then
        mkdir -p /Volumes/Anka/${username}/img_lib /Volumes/Anka/${username}/state_lib /Volumes/Anka/${username}/vm_lib/.locks
    fi
    chown -R ${username} /Volumes/Anka/${username}
    ${USER_SWITCH} anka config img_lib_dir "/Volumes/Anka/${username}/img_lib"
    ${USER_SWITCH} anka config state_lib_dir "/Volumes/Anka/${username}/state_lib"
    ${USER_SWITCH} anka config vm_lib_dir "/Volumes/Anka/${username}/vm_lib"
    ${USER_SWITCH} anka config vm_lock_dir "/Volumes/Anka/${username}/vm_lib/.locks"
done
EOF

chmod +x /usr/local/bin/prepare-local-disk
cat >> /usr/local/aws/ec2-macos-init/init.toml <<'EOF'

[[Module]]
    Name = "PrepareLocalDisk"
    PriorityGroup = 4
    RunPerBoot = true # Run every boot
    FatalOnError = false # Best effort, don't fatal on error
    [Module.Command]
        Cmd = ["/bin/zsh", "-c", "sudo /usr/local/bin/prepare-local-disk | sudo tee -a /var/log/prepare-local-disk.log"]

EOF

/usr/local/bin/prepare-local-disk