#/usr/bin/env bash
set -exo pipefail
unset HISTFILE
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root using sudo anklet-install.bash"
  exit 1
fi
. ./_helpers.bash
ANKA_ANKLET_PLIST_LOG_DIR="${ANKA_ANKLET_PLIST_LOG_DIR:-"/tmp"}"
sudo -u ec2-user brew install logrotate
mkdir -p /opt/homebrew/etc/logrotate.d
cat <<EOF > /opt/homebrew/etc/logrotate.d/anklet
${ANKA_ANKLET_PLIST_LOG_DIR}/anklet-plist.err.log {
    daily
    rotate 4
    compress
    delaycompress
    missingok
    copytruncate
    maxsize 1G
    create 0777 ec2-user staff
    dateformat -%Y%m%d_%H:%M:%S
}
${ANKA_ANKLET_PLIST_LOG_DIR}/anklet-plist.out.log {
    daily
    rotate 4
    compress
    delaycompress
    missingok
    copytruncate
    maxsize 1G
    create 0777 ec2-user staff
    dateformat -%Y%m%d_%H:%M:%S
}
EOF
# the default plist for logrotate is not good enough.
# Find the correct homebrew logrotate plist file regardless of version
LOGROTATE_PLIST_PATH=$(ls /opt/homebrew/Cellar/logrotate/*/homebrew.mxcl.logrotate.plist | head -n 1)
cat <<EOF > "${LOGROTATE_PLIST_PATH}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>homebrew.mxcl.logrotate</string>
	<key>LimitLoadToSessionType</key>
	<array>
		<string>Aqua</string>
		<string>Background</string>
		<string>LoginWindow</string>
		<string>StandardIO</string>
		<string>System</string>
	</array>
	<key>ProgramArguments</key>
	<array>
		<string>/opt/homebrew/opt/logrotate/sbin/logrotate</string>
		<string>/opt/homebrew/etc/logrotate.conf</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>StartInterval</key>
	<integer>60</integer>
</dict>
</plist>
EOF
sudo chown ec2-user:staff /opt/homebrew/etc/logrotate.conf
sudo chown ec2-user:staff /opt/homebrew/etc/logrotate.d/anklet
sudo -u ec2-user brew services start logrotate
launchctl unload -w /Library/LaunchDaemons/com.veertu.anklet.plist || true
# Create the plist file
cat <<EOF > /Library/LaunchDaemons/com.veertu.anklet.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.veertu.anklet</string>
    <key>EnvironmentVariables</key>
    <dict>
      <key>HOME</key>
      <string>/Users/${AWS_INSTANCE_USER}</string>
    </dict>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>-l</string>
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
    <key>StandardErrorPath</key>
    <string>${ANKA_ANKLET_PLIST_LOG_DIR}/anklet-plist.err.log</string>
    <key>StandardOutPath</key>
    <string>${ANKA_ANKLET_PLIST_LOG_DIR}/anklet-plist.out.log</string> 
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
set +x
echo "Anklet has been installed and loaded."
echo "You can control it with the following commands:"
echo "  sudo launchctl start com.veertu.anklet"
echo "  sudo launchctl stop com.veertu.anklet"
echo "  sudo launchctl unload -w /Library/LaunchDaemons/com.veertu.anklet.plist"
echo "  sudo launchctl load -w /Library/LaunchDaemons/com.veertu.anklet.plist"
set -x
launchctl load -w /Library/LaunchDaemons/com.veertu.anklet.plist
launchctl start com.veertu.anklet || true
