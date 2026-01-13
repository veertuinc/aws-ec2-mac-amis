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

tee /usr/local/bin/prepare-local-disk >/dev/null <<'EOF'
#!/bin/bash
set -exo pipefail

diskutil list

if ! diskutil info /dev/disk4 &>/dev/null; then
    echo "Disk /dev/disk4 does not exist. Exiting."
    exit 1
fi

if diskutil list /dev/disk4 | grep -q disk4s1; then
    echo "Disk already formatted, mounting and exiting"
    diskutil mountDisk /dev/disk4
else
    echo "Disk not formatted, formatting and exiting"
    diskutil eraseDisk APFS "Anka" /dev/disk4
fi

diskutil list /dev/disk4
if [[ -d /Volumes/Anka/root/img_lib ]]; then
    echo "Anka volumes already created, exiting"
    exit 0
fi
for username in root ec2-user; do
    echo "Preparing ${username}..."
    [[ "${username}" != "root" ]] && USER_SWITCH="sudo -u ${username}"
    mkdir -p /Volumes/Anka/${username}/img_lib /Volumes/Anka/${username}/state_lib /Volumes/Anka/${username}/vm_lib/.locks
    chown -R ${username} /Volumes/Anka/${username}
    ${USER_SWITCH} anka config img_lib_dir "/Volumes/Anka/${username}/img_lib"
    ${USER_SWITCH} anka config state_lib_dir "/Volumes/Anka/${username}/state_lib"
    ${USER_SWITCH} anka config vm_lib_dir "/Volumes/Anka/${username}/vm_lib"
    ${USER_SWITCH} anka config vm_lock_dir "/Volumes/Anka/${username}/vm_lib/.locks"
done
EOF

chmod +x /usr/local/bin/prepare-local-disk
tee -a /usr/local/aws/ec2-macos-init/init.toml >/dev/null <<'EOF'

[[Module]]
    Name = "PrepareLocalDisk"
    PriorityGroup = 4
    RunPerBoot = true # Run every boot
    FatalOnError = false # Best effort, don't fatal on error
    [Module.Command]
        Cmd = ["/bin/zsh", "-c", "sudo /usr/local/bin/prepare-local-disk | sudo tee -a /var/log/prepare-local-disk.log"]

EOF

/usr/local/bin/prepare-local-disk