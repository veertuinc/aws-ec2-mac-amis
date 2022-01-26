#!/bin/bash
set -exo pipefail
[[ ! $EUID -eq 0 ]] && echo "RUN AS ROOT!" && exit 1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
echo "Waiting for networking..."
while ! ping -c 1 -n github.com &> /dev/null; do sleep 1; done
. ./_helpers.bash
disjoin() {
  echo "$(date) $(whoami) Received a signal to shutdown"
  set -x
  rm -f /tmp/wait-fifo
  /usr/local/bin/ankacluster disjoin &
  CERTS=""
  [[ ! -z "$CLOUD_CONNECT_CERT" ]] && CERTS="--cert $CLOUD_CONNECT_CERT"
  [[ ! -z "$CLOUD_CONNECT_KEY" ]] && CERTS="$CERTS --cert-key $CLOUD_CONNECT_KEY"
  [[ ! -z "$CLOUD_CONNECT_CA" ]] && CERTS="$CERTS --cacert $CLOUD_CONNECT_CA"
  NODE_ID="$(curl -s $CERTS "${ANKA_CONTROLLER_ADDRESS}/api/v1/node" | jq -r ".body | .[] | select(.node_name==\"$(hostname)\") | .node_id")"
  curl -s $CERTS -X DELETE "${ANKA_CONTROLLER_ADDRESS}/api/v1/node" -H "Content-Type: application/json" -d "{\"node_id\": \"$NODE_ID\"}"
  wait $!
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
      <string>/Users/$AWS_INSTANCE_USER/aws-ec2-mac-amis/cloud-connect.bash</string>
      <string>${ANKA_JOIN_ARGS}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>/Users/$AWS_INSTANCE_USER</string>
    <key>StandardErrorPath</key>
    <string>/var/log/cloud-connect.log</string>
    <key>StandardOutPath</key>
    <string>/var/log/cloud-connect.log</string>
    <key>ExitTimeOut</key>
    <string>300</string>
  </dict>
  </plist>
EOD
  launchctl load -w $CLOUD_CONNECT_PLIST_PATH
else
  echo "$(date) ($(whoami)): Attempting join..."
  # Check if user-data exists
  [[ ! -z "$(curl -s http://169.254.169.254/latest/user-data | grep 404)" ]] && echo "Could not find required ANKA_CONTROLLER_ADDRESS in instance user-data!" && exit 1
  sudo sed -i '' "/anka.registry/d" /etc/hosts # Remove hosts modifications for automation (INTERNAL ONLY)
  # create user ENVs for this session
  eval "$(curl -s http://169.254.169.254/latest/user-data | grep "ANKA_")" # EVAL needed to handle quotes wrapping ARGS ENV
  INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
  # IF the user wants to change the IP address for the registry domain name (if they want to use a second EC2 registry for better speed), handle setting the /etc/hosts
  if [[ ! -z "$ANKA_REGISTRY_OVERRIDE_IP" && ! -z "$ANKA_REGISTRY_OVERRIDE_DOMAIN" ]]; then
    modify_hosts $ANKA_REGISTRY_OVERRIDE_DOMAIN $ANKA_REGISTRY_OVERRIDE_IP
  fi
  # Join arguments
  ANKA_JOIN_ARGS="${ANKA_JOIN_ARGS:-"$*"}"
  [[ ! "${ANKA_JOIN_ARGS}" =~ "--node-id" ]] && ANKA_JOIN_ARGS="${ANKA_JOIN_ARGS} --node-id ${INSTANCE_ID}"
  [[ ! "${ANKA_JOIN_ARGS}" =~ "--reserve-space" ]] && ANKA_JOIN_ARGS="${ANKA_JOIN_ARGS} --reserve-space 20GB"
  # Anka agent install to handle it failing
  curl -O ${ANKA_CONTROLLER_ADDRESS}/pkg/AnkaAgent.pkg && installer -pkg AnkaAgent.pkg -tgt / && rm -f AnkaAgent.pkg
  anka license accept-eula 2>/dev/null || true
  if [[ -n "${ANKA_LICENSE}" ]]; then # Activate license if present
    anka license show
    if ! anka --machine-readable license show | grep 'status": "valid"'; then
      echo "Activating anka license..."
      anka license activate -f "${ANKA_LICENSE}" || true
    fi
    anka license show
  fi
  /usr/local/bin/ankacluster disjoin || true
  /usr/local/bin/ankacluster join $ANKA_CONTROLLER_ADDRESS $ANKA_JOIN_ARGS
  trap disjoin 0 # Disjoin after we joined properly to avoid unloading prematurely
  set +x
  echo "Joined and now we'll stay alive and wait for a shutdown signal..."
  mkfifo /tmp/wait-fifo; read < /tmp/wait-fifo
fi