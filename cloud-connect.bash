#!/bin/bash
set -exo pipefail
[[ ! $EUID -eq 0 ]] && echo "RUN AS ROOT!" && exit 1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
git pull
. ./_helpers.bash
# Grab the ENVS the user sets in user-data
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
  # create user ENVs for this session
  $(curl -s http://169.254.169.254/latest/user-data| sed 's/\"//g')
  # Check if user-data exists
  [[ ! -z "$(curl -s http://169.254.169.254/latest/user-data | grep 404)" ]] && echo "Could not find required ANKA_CONTROLLER_ADDRESS in instance user-data!" && exit 1
  # IF the user wants to change the IP address for the registry domain name (if they want to use a second EC2 registry for better speed), handle setting the /etc/hosts
  if [[ ! -z "$ANKA_REGISTRY_OVERRIDE_IP" && ! -z "$ANKA_REGISTRY_OVERRIDE_DOMAIN" ]]; then
      modify_hosts $ANKA_REGISTRY_OVERRIDE_DOMAIN $ANKA_REGISTRY_OVERRIDE_IP
  fi
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