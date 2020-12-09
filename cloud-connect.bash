#!/bin/bash
set -exo pipefail
[[ ! $EUID -eq 0 ]] && echo "RUN AS ROOT!" && exit 1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
git pull
. ./_helpers.bash
# Grab the ENVS the user sets in user-data
$(curl -s http://169.254.169.254/latest/user-data| sed 's/\"//g')
if [[ ! -e $CLOUD_CONNECT_PLIST_PATH ]]; then
  mkdir -p $LAUNCH_LOCATION
cat > $CLOUD_CONNECT_PLIST_PATH <<EOD
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
	<dict>
		<key>Label</key>
		<string>aws-ec2-mac-amis.cloud-connect</string>
		<key>ProgramArguments</key>
		<array>
      <string>/usr/bin/env</string>
      <string>bash</string>
      <string>-c</string>
      <string>/Users/ec2-user/aws-ec2-mac-amis/cloud-connect.bash</string>
    </array>
		<key>RunAtLoad</key>
		<true/>
		<key>KeepAlive</key>
		<true/>
		<key>ExitTimeOut</key>
		<integer>300</integer>
    <key>WorkingDirectory</key>
    <string>/Users/ec2-user</string>
    <key>StandardErrorPath</key>
    <string>/var/log/cloud-connect.log</string>
    <key>StandardOutPath</key>
    <string>/var/log/cloud-connect.log</string>
	</dict>
</plist>
EOD
  launchctl load -w $CLOUD_CONNECT_PLIST_PATH
else
  # Ensure that anytime the script stops, we disjoin first
  disjoin() {
    set -x
    /usr/local/bin/ankacluster disjoin
  }
  trap disjoin EXIT
  /usr/local/bin/ankacluster join $ANKA_CONTROLLER_ADDRESS $ANKA_JOIN_ARGS
  set +x
  while true; do
    sleep 1
  done
fi