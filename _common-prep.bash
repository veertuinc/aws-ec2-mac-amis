GETTING_STARTED_LOCATION="$HOME/getting-started"
# POPULATE .zshrc
[[ -z "$(grep "alias ll" $HOME/.zshrc)" ]] && echo "" >> $HOME/.zshrc && echo "alias ll=\"ls -laht\"" >> $HOME/.zshrc
# Ensure the query tool exists
[[ ! -e "/usr/local/bin/ec2-metadata" ]] && curl http://s3.amazonaws.com/ec2metadata/ec2-metadata -o /usr/local/bin/ec2-metadata && chmod +x /usr/local/bin/ec2-metadata
# Install Anka
if [[ ! -d "$HOME/getting-started" ]]; then
  pushd $HOME
    git clone https://github.com/veertuinc/getting-started.git
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

# Enable VNC
cd /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/
sudo ./kickstart -configure -allowAccessFor -specifiedUsers
sudo ./kickstart -configure -allowAccessFor -allUsers -privs -all
sudo ./kickstart -activate

# sleep settings
sudo systemsetup -setcomputersleep Off
systemsetup -setcomputersleep Off || true
sudo pmset -a standby 0
sudo pmset -a disksleep 0
sudo pmset -a hibernatemode 0