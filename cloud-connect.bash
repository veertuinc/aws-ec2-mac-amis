#!/bin/bash
set -exo pipefail
[[ ! $EUID -eq 0 ]] && echo "RUN AS ROOT!" && exit 1
export PATH="${PATH}:/opt/homebrew/bin:/opt/homebrew/sbin" # support new arm brew location
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
  if [[ -n "${ANKA_CONTROLLER_ADDRESS}" ]]; then
    NODE_ID="$(curl -s ${ANKA_CONTROLLER_API_CERTS} "${ANKA_CONTROLLER_ADDRESS}/api/v1/node" | jq -r ".body | .[] | select(.node_name==\"$(hostname)\") | .node_id")"
    curl -s ${ANKA_CONTROLLER_API_CERTS} -X DELETE "${ANKA_CONTROLLER_ADDRESS}/api/v1/node" -H "Content-Type: application/json" -d "{\"node_id\": \"$NODE_ID\"}"
  fi
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
    <key>KeepAlive</key>
    <dict>
      <key>SuccessfulExit</key>
      <false/>
    </dict>
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
  if [[ ! -z "$(curl -s http://169.254.169.254/latest/user-data | grep 404)" || -z "$(curl -s http://169.254.169.254/latest/user-data)" ]]; then
    echo "Could not find any user-data for instance..."
    disjoin || true
    exit 1
  fi
  sudo sed -i '' "/anka.registry/d" /etc/hosts # Remove hosts modifications for automation (INTERNAL ONLY)
  # create user ENVs for this session
  eval "$(curl -s http://169.254.169.254/latest/user-data | grep "ANKA_")" # eval needed to handle quotes wrapping ARGS ENV
  INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
  INSTANCE_PRIVATE_IP="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
  INSTANCE_PUBLIC_IP="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
  # IF the user wants to change the IP address for the registry domain name (if they want to use a second EC2 registry for better speed), handle setting the /etc/hosts
  if [[ -n "${ANKA_REGISTRY_OVERRIDE_IP}" && -n "${ANKA_REGISTRY_OVERRIDE_DOMAIN}" ]]; then
    modify_hosts $ANKA_REGISTRY_OVERRIDE_DOMAIN $ANKA_REGISTRY_OVERRIDE_IP
  fi
  # Certificate support
  ANKA_CONTROLLER_API_CERTS="${ANKA_CONTROLLER_API_CERTS:-""}"
  if [[ -z "${ANKA_CONTROLLER_API_CERTS}" && -n "${ANKA_CONTROLLER_API_CERT}" ]]; then
    ANKA_CONTROLLER_API_CERTS="--cert ${ANKA_CONTROLLER_API_CERT}"
    if [[ -n "${ANKA_CONTROLLER_API_KEY}" ]]; then
      ANKA_CONTROLLER_API_CERTS="${ANKA_CONTROLLER_API_CERTS} --cert-key ${ANKA_CONTROLLER_API_KEY}"
    else
      echo "missing controller cert key" && exit 2
    fi
    [[ -n "${ANKA_CONTROLLER_API_CA}" ]] && ANKA_CONTROLLER_API_CERTS="${ANKA_CONTROLLER_API_CERTS} --cacert ${ANKA_CONTROLLER_API_CA}"
  fi
  ANKA_REGISTRY_API_CERTS="${ANKA_REGISTRY_API_CERTS:-""}"
  if [[ -z "${ANKA_REGISTRY_API_CERTS}" && -n "${ANKA_REGISTRY_API_CERT}" ]]; then
    ANKA_REGISTRY_API_CERTS="--cert ${ANKA_REGISTRY_API_CERT}"
    if [[ -n "${ANKA_REGISTRY_API_KEY}" ]]; then
      ANKA_REGISTRY_API_CERTS="${ANKA_REGISTRY_API_CERTS} --cert-key ${ANKA_REGISTRY_API_KEY}"
    else
      echo "missing registry cert key" && exit 2
    fi
    [[ -n "${ANKA_REGISTRY_API_CA}" ]] && ANKA_REGISTRY_API_CERTS="${ANKA_REGISTRY_API_CERTS} --cacert ${ANKA_REGISTRY_API_CA}"
  fi
  # Join arguments
  ANKA_JOIN_ARGS="${ANKA_JOIN_ARGS:-"$*"}" # used for older getting started script + enables overriding defaults from inside plist instead of user-data
  if sudo ankacluster join --help | grep "node-id"; then # make sure we don't try to join with --node-id unless it's an available option for ankacluster
    [[ ! "${ANKA_JOIN_ARGS}" =~ "--node-id" ]] && ANKA_JOIN_ARGS="${ANKA_JOIN_ARGS} --node-id ${INSTANCE_ID}"
  fi
  [[ ! "${ANKA_JOIN_ARGS}" =~ "--reserve-space" ]] && ANKA_JOIN_ARGS="${ANKA_JOIN_ARGS} --reserve-space 20GB"
  ${ANKA_USE_PUBLIC_IP:-false} && INSTANCE_IP="${INSTANCE_PUBLIC_IP}" || INSTANCE_IP="${INSTANCE_PRIVATE_IP}"
  [[ ! "${ANKA_JOIN_ARGS}" =~ "--host" ]] && ANKA_JOIN_ARGS="${ANKA_JOIN_ARGS} --host ${INSTANCE_IP}"
  anka license accept-eula 2>/dev/null || true
  if [[ -n "${ANKA_LICENSE}" ]]; then # Activate license if present
    anka license show
    if ! anka --machine-readable license show | grep 'status": "valid"'; then
      echo "Activating anka license..."
      ANKA_LICENSE_ACTIVATE_STDOUT="$(anka license activate -f "${ANKA_LICENSE}" || true)"
      echo "${ANKA_LICENSE_ACTIVATE_STDOUT}"
      # Post the fulfillment ID to the centralized logs
      ANKA_CONTROLLER_CONFIG_REGISTRY_ADDRESS="$(curl -s ${ANKA_CONTROLLER_API_CERTS} ${ANKA_CONTROLLER_ADDRESS}/api/v1/status | jq -r '.body.registry_address')"
      curl ${ANKA_REGISTRY_API_CERTS} -v "${ANKA_CONTROLLER_CONFIG_REGISTRY_ADDRESS}/log" -d "{\"machine_name\": \"${INSTANCE_ID} | $(system_profiler SPHardwareDataType | grep 'Hardware UUID' | awk '{print $NF}')\", \"service\": \"AWS Cloud Connect Service\", \"host\": \"\", \"content\": \"${ANKA_LICENSE_ACTIVATE_STDOUT}\"}"
    fi
    anka license show
  fi
  /usr/local/bin/ankacluster disjoin || true
  sleep 10 # AWS instances, on first start, and even with functional networking (we ping github.com above), will have 169.254.169.254 assigned to the default interface and since joining happens very early in the startup process, that'll be what is assigned in the controller and cause problems.
  /usr/local/bin/ankacluster join ${ANKA_CONTROLLER_ADDRESS} ${ANKA_JOIN_ARGS}
  trap disjoin 0 # Disjoin after we joined properly to avoid unloading prematurely
  set +x
  echo "Joined and now we'll stay alive and wait for a shutdown signal..."
  mkfifo /tmp/wait-fifo; read < /tmp/wait-fifo
fi