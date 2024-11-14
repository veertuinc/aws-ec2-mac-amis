#/usr/bin/env bash
set -exo pipefail
unset HISTFILE
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root using sudo anklet-install.bash"
  exit 1
fi
. ./_helpers.bash
launchctl unload -w /Library/LaunchDaemons/com.veertu.anklet.plist || true
# Create the plist file
cat <<EOF > /Library/LaunchDaemons/com.veertu.anklet.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.veertu.anklet</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/anklet</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/tmp/</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>AssociatedBundleIdentifiers</key>
    <string>com.veertu.anklet</string>
</dict>
</plist>
EOF
ARCH=$([[ $(arch) == "arm64" ]] && echo "arm64" || echo "amd64")
LATEST_VERSION=$(curl -sL https://api.github.com/repos/veertuinc/anklet/releases | jq -r '.[0].tag_name')
curl -L -O https://github.com/veertuinc/anklet/releases/download/"${LATEST_VERSION}"/anklet_v"${LATEST_VERSION}"_darwin_"${ARCH}".zip
unzip -o anklet_v"${LATEST_VERSION}"_darwin_"${ARCH}".zip
chmod +x anklet_v"${LATEST_VERSION}"_darwin_"${ARCH}"
cp anklet_v"${LATEST_VERSION}"_darwin_"${ARCH}" /usr/local/bin/anklet
mkdir -p ~/.config/
cd ~/.config/
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
if [[ -d anklet ]]; then
  pushd anklet
    if [[ ! -d .git ]]; then
      git init
      git config core.sparseCheckout true
      git remote add origin https://github.com/veertuinc/anklet.git
      git sparse-checkout set plugins
      git fetch origin main
      git checkout main
    fi
  popd
else
  git clone --no-checkout --depth=1 --filter=blob:none https://github.com/veertuinc/anklet.git
  pushd anklet
    git reset -q -- \
      plugins
    git checkout-index -a -f
  popd
fi
if [[ -n "${ANKA_EXECUTE_SCRIPT_CONFIG}" ]]; then
  printf "%b" "${ANKA_EXECUTE_SCRIPT_CONFIG}" > ~/.config/anklet/config.yml
else 
  echo "WARNING: Be sure to create your ~/.config/anklet/config.yml before loading!"
fi
[[ $(whoami) == "ec2-user" ]] && sudo chown -R $AWS_INSTANCE_USER:staff ~/.config
echo "Anklet has been installed and loaded."
echo "You can control it with the following commands:"
echo "  sudo launchctl start com.veertu.anklet"
echo "  sudo launchctl stop com.veertu.anklet"
echo "  sudo launchctl unload -w /Library/LaunchDaemons/com.veertu.anklet.plist"
echo "  sudo launchctl load -w /Library/LaunchDaemons/com.veertu.anklet.plist"
sudo launchctl load -w /Library/LaunchDaemons/com.veertu.anklet.plist
sudo launchctl start com.veertu.anklet || true
