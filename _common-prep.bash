GETTING_STARTED_LOCATION="$HOME/getting-started"
# POPULATE .zshrc
[[ -z "$(grep "alias ll" $HOME/.zshrc)" ]] && echo "" >> $HOME/.zshrc && echo "alias ll=\"ls -laht\"" >> $HOME/.zshrc
# Ensure the query tool exists
[[ ! -e "/usr/local/bin/ec2-metadata" ]] && curl http://s3.amazonaws.com/ec2metadata/ec2-metadata -o /usr/local/bin/ec2-metadata && chmod +x /usr/local/bin/ec2-metadata
# Install Anka
if [[ ! -d "$HOME/getting-started" ]]; then
  pushd $HOME
    git clone https://github.com/veertuinc/getting-started.git $GETTING_STARTED_CLONE_BRANCH
  popd
fi
brew install jq # used for cloud-connect api parsing
pushd $GETTING_STARTED_LOCATION
git pull
ANKA_LICENSE=${ANKA_LICENSE:-""}
[[ -z $(command -v anka) ]] && ./install-anka-virtualization-on-mac.bash
popd

# Disable indexing volumes
sudo defaults write ~/.Spotlight-V100/VolumeConfiguration.plist Exclusions -array "/Volumes"
sudo defaults write ~/.Spotlight-V100/VolumeConfiguration.plist Exclusions -array "/Network"
sudo killall mds || true
sleep 60
sudo mdutil -a -i off /
sudo mdutil -a -i off
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.metadata.mds.plist
sudo rm -rf /.Spotlight-V100/*

# Enable VNC
pushd /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/
sudo ./kickstart -configure -allowAccessFor -specifiedUsers
sudo ./kickstart -configure -allowAccessFor -allUsers -privs -all
sudo ./kickstart -activate
popd

# Sleep settings ; MAY BE USELESS AS AMIS DON'T SAVE NVRAM SETTINGS
sudo systemsetup -setsleep Never || true
sudo systemsetup -setcomputersleep Off
systemsetup -setcomputersleep Off || true
sudo pmset -a standby 0
sudo pmset -a disksleep 0
sudo pmset -a hibernatemode 0

# Optimizations for templates
anka config chunk_size 2147483648
sudo anka config chunk_size 2147483648

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

# Performance related changes
anka config block_nocache 0
sudo anka config block_nocache 0

# Disable sleep and screensaver so we don't need to disable "Require password after sleep or screensaver begins"
sudo cat << EOF | sudo tee -a /usr/local/aws/ec2-macos-init/init.toml
[[Module]]
    Name = "DisableScreenSaver"
    PriorityGroup = 4
    RunPerBoot = true # Run every boot
    FatalOnError = false # Best effort, don't fatal on error
    [Module.Command]
        Cmd = ["/bin/zsh", "-c", 'sudo defaults write com.apple.screensaver idleTime 0']
EOF
sudo cat << EOF | sudo tee -a /usr/local/aws/ec2-macos-init/init.toml
[[Module]]
    Name = "DisableSleep"
    PriorityGroup = 4
    RunPerBoot = true # Run every boot
    FatalOnError = false # Best effort, don't fatal on error
    [Module.Command]
        Cmd = ["/bin/zsh", "-c", 'sudo systemsetup -setsleep Never']
EOF
