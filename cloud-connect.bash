#!/bin/bash
set -exo pipefail
[[ ! $EUID -eq 0 ]] && echo "RUN AS ROOT!" && exit 1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
echo "Waiting for networking..."
while ! ping -c 1 -n github.com &> /dev/null; do sleep 1; done
git pull
. ./_helpers.bash
disjoin() {
  set -x
  /usr/local/bin/ankacluster disjoin &
  CERTS=""
  [[ ! -z "$CLOUD_CONNECT_CERT" ]] && CERTS="--cert $CLOUD_CONNECT_CERT"
  [[ ! -z "$CLOUD_CONNECT_KEY" ]] && CERTS="$CERTS --cert-key $CLOUD_CONNECT_KEY"
  [[ ! -z "$CLOUD_CONNECT_CA" ]] && CERTS="$CERTS --cacert $CLOUD_CONNECT_CA"
  NODE_ID="$(curl -s $CERTS "${ANKA_CONTROLLER_ADDRESS}/api/v1/node" | jq -r ".body | .[] | select(.node_name==\"$(hostname)\") | .node_id")"
  curl -s $CERTS -X DELETE "${ANKA_CONTROLLER_ADDRESS}/api/v1/node" -H "Content-Type: application/json" -d "{\"node_id\": \"$NODE_ID\"}"
}
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
  echo "$(date) ($(whoami)): Attempting join..."
  # Check if user-data exists
  [[ ! -z "$(curl -s http://169.254.169.254/latest/user-data | grep 404)" ]] && echo "Could not find required ANKA_CONTROLLER_ADDRESS in instance user-data!" && exit 1
  # create user ENVs for this session
  $(curl -s http://169.254.169.254/latest/user-data| sed 's/\"//g') 
  # IF the user wants to change the IP address for the registry domain name (if they want to use a second EC2 registry for better speed), handle setting the /etc/hosts
  if [[ ! -z "$ANKA_REGISTRY_OVERRIDE_IP" && ! -z "$ANKA_REGISTRY_OVERRIDE_DOMAIN" ]]; then
      modify_hosts $ANKA_REGISTRY_OVERRIDE_DOMAIN $ANKA_REGISTRY_OVERRIDE_IP
  fi
  # Ensure that anytime the script stops, we disjoin first
  /usr/local/bin/ankacluster join $ANKA_CONTROLLER_ADDRESS $ANKA_JOIN_ARGS
  trap disjoin 0 # Disjoin after we joined properly to avoid unloading prematurely
  set +x
  while true; do
    sleep 1
  done
fi