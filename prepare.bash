#!/bin/bash
set -exo pipefail
unset HISTFILE
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ./_helpers.bash

GETTING_STARTED_LOCATION="$HOME/getting-started"
# POPULATE .zshrc
## In 15.5 AMIs, amazon is changing .zshrc and chowning it to root... Fix that...
sudo chown $AWS_INSTANCE_USER:staff $HOME/.zshrc
[[ -z "$(grep "alias ll" $HOME/.zshrc)" ]] && echo "" >> $HOME/.zshrc && echo "alias ll=\"ls -laht\"" >> $HOME/.zshrc
source ~/.zshrc || true
# Ensure the query tool exists ; AWS has deprecated it
# [[ ! -e "/usr/local/bin/ec2-metadata" ]] && curl http://s3.amazonaws.com/ec2metadata/ec2-metadata -o /usr/local/bin/ec2-metadata && chmod +x /usr/local/bin/ec2-metadata

[[ -f "./${AMI_MACOS_TARGET_VERSION}.bash" ]] && ./"${AMI_MACOS_TARGET_VERSION}".bash

# Install resize disk plist
[[ ! -e "${RESIZE_DISK_PLIST_PATH}" ]] && sudo -E bash -c "pwd; ./resize-disk.bash"

# Install Anka
brew install jq # used for cloud-connect api parsing
pushd "${HOME}"
  rm -rf getting-started
  git clone https://github.com/veertuinc/getting-started.git
  cd getting-started
  ANKA_LICENSE=${ANKA_LICENSE:-""}
  [[ -n "${ANKA_TARGET_VERSION}" ]] && export ANKA_VIRTUALIZATION_PACKAGE="Anka-${ANKA_TARGET_VERSION}.pkg"
  ./install-anka-virtualization-on-mac.bash
popd

# Disable indexing volumes
sudo defaults write ~/.Spotlight-V100/VolumeConfiguration.plist Exclusions -array "/Volumes" || true
sudo defaults write ~/.Spotlight-V100/VolumeConfiguration.plist Exclusions -array "/Network" || true
sudo killall mds || true
sleep 60
sudo mdutil -a -i off / || true
sudo mdutil -a -i off || true
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.metadata.mds.plist || true
sudo rm -rf /.Spotlight-V100/*
rm -rf ~/Library/Metadata/CoreSpotlight/ || true
killall -KILL Spotlight spotlightd mds || true
sudo rm -rf /System/Volums/Data/.Spotlight-V100 || true

# Enable VNC
## Disabled as it now throws a warning and doesn't work.
## Screen recording might be disabled. Screen Sharing or Remote Management must be enabled from System Preferences or via MDM.
## Screen control might be disabled. Screen Sharing or Remote Management must be enabled from System Preferences or via MDM.
# sudo defaults write /var/db/launchd.db/com.apple.launchd/overrides.plist com.apple.screensharing -dict Disabled -bool false
# sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist
# old legacy ----
# pushd /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/
# sudo ./kickstart -configure -allowAccessFor -specifiedUsers
# sudo ./kickstart -configure -allowAccessFor -allUsers -privs -all
# sudo ./kickstart -activate
# popd

# Sleep settings ; MAY BE USELESS AS AMIS DON'T SAVE NVRAM SETTINGS
sudo systemsetup -setsleep Never
sudo systemsetup -setcomputersleep Off
systemsetup -setcomputersleep Off || true
sudo pmset -a standby 0
sudo pmset -a disksleep 0
sudo pmset -a hibernatemode 0
defaults write com.apple.screensaver idleTime 0

# Required to create necessary folders | No such file or directory: '/var/root/Library/Application Support/Veertu/Anka/img_lib/' from agent
anka create test && anka delete --yes test
sudo anka create test && sudo anka delete --yes test

# SSH will break with Broken pipe when doing anka create
sudo cat << EOF | sudo tee /etc/ssh/sshd_config.d/051-anka.conf
ClientAliveInterval 900
ClientAliveCountMax 220
EOF

# syslog spam com.apple.xpc.launchd[1] (com.apple.wifi.WiFiAgent): Service only ran for 0 seconds. Pushing respawn out by 10 seconds.
launchctl unload -w /System/Library/LaunchAgents/com.apple.wifi.WiFiAgent.plist || true

# Performance related changes / DISABLED AS OF 2.5.5 due to it freezing anka create
# anka config block_nocache 0
# sudo anka config block_nocache 0

# Disable sleep and screensaver so we don't need to disable "Require password after sleep or screensaver begins"
if ! grep -q DisableScreenSaver /usr/local/aws/ec2-macos-init/init.toml; then
sudo cat << EOF | sudo tee -a /usr/local/aws/ec2-macos-init/init.toml
[[Module]]
    Name = "DisableScreenSaver"
    PriorityGroup = 4
    RunPerBoot = true # Run every boot
    FatalOnError = false # Best effort, don't fatal on error
    [Module.Command]
        Cmd = ["/bin/zsh", "-c", 'defaults write com.apple.screensaver idleTime 0']
EOF
fi
if ! grep -q DisableSleep /usr/local/aws/ec2-macos-init/init.toml; then
sudo cat << EOF | sudo tee -a /usr/local/aws/ec2-macos-init/init.toml
[[Module]]
    Name = "DisableSleep"
    PriorityGroup = 4
    RunPerBoot = true # Run every boot
    FatalOnError = false # Best effort, don't fatal on error
    [Module.Command]
        Cmd = ["/bin/zsh", "-c", 'sudo systemsetup -setsleep Never']
EOF
fi
unset HISTFILE

# Create plist for cloud connect # Should be last!
[[ ! -e $CLOUD_CONNECT_PLIST_PATH ]] && sudo -E bash -c "./cloud-connect.bash"

sudo chown -R $AWS_INSTANCE_USER:staff ~/aws-ec2-mac-amis
# error: cannot open '.git/FETCH_HEAD': Permission denied
sudo chown -R $AWS_INSTANCE_USER:staff ~/aws-ec2-mac-amis/.git

brew install openssl # needed for UAK support in cloud-connect

# Increase buffer sizes for faster image transfer
sudo anka config recv_buffer_size 16777216
sudo anka config send_buffer_size 16777216
anka config recv_buffer_size 16777216
anka config send_buffer_size 16777216

echo "done" > ~/prep
unset HISTFILE