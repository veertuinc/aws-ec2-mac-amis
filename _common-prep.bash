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
sudo killall mds
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

# Sleep settings
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
