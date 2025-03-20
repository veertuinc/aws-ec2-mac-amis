#!/bin/bash
set -exo pipefail
echo ""
echo "]] ANKA CLOUD CONNECT SCRIPT STARTED"
[[ ! $EUID -eq 0 ]] && echo "RUN AS ROOT!" && exit 1
export HOME="/Users/ec2-user/" # git config --global --add safe.directory /Users/ec2-user/aws-ec2-mac-amis fatal: $HOME not set
export PATH="/opt/homebrew/bin:$PATH"
export PATH="${PATH}:$(brew --prefix)/bin:$(brew --prefix)/sbin" # support new arm brew location
export PATH="${PATH}:$(brew --prefix)/opt/openssl/bin" # support for OpenSSL and UAK
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
export CLOUD_CONNECT_JOINED_FILE=".cloud-connect-joined"
[[ "$(du -sk /var/log/cloud-connect.log | awk '{print $1/1024}' | cut -d. -f1)" -gt 100 ]] && echo "" > /var/log/cloud-connect.log # empty log file so that it doesn't grow uncontrollably.
echo "Waiting for networking..."
while ! ping -c 1 -n github.com &> /dev/null; do sleep 1; done
. ./_helpers.bash
disjoin() {
  echo "$(date) $(whoami) Received a signal to shutdown"
  set -x
  if [[ -f "${CLOUD_CONNECT_JOINED_FILE}" ]]; then # Only disjoin if cloud-connect joined us previously
    rm -f /tmp/wait-fifo
    /usr/local/bin/ankacluster disjoin &
    rm -f "${CLOUD_CONNECT_JOINED_FILE}"
    if [[ -n "${ANKA_CONTROLLER_ADDRESS}" ]]; then
      NODE_ID="$(do_curl -s ${ANKA_CONTROLLER_API_AUTH} "${ANKA_CONTROLLER_ADDRESS}/api/v1/node" | jq -r ".body | .[] | select(.node_name==\"$(hostname)\") | .node_id")"
      do_curl -s ${ANKA_CONTROLLER_API_AUTH} -X DELETE "${ANKA_CONTROLLER_ADDRESS}/api/v1/node" -H "Content-Type: application/json" -d "{\"node_id\": \"$NODE_ID\"}"
    fi
    wait $!
  fi
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
  <key>WorkingDirectory</key>
  <string>/Users/$AWS_INSTANCE_USER</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>StandardErrorPath</key>
  <string>/var/log/cloud-connect.log</string>
  <key>StandardOutPath</key>
  <string>/var/log/cloud-connect.log</string>
  <key>ExitTimeOut</key>
  <string>300</string>
  <key>AssociatedBundleIdentifiers</key>
  <string>com.veertu.anka</string>
</dict>
</plist>
EOD
  launchctl load -w $CLOUD_CONNECT_PLIST_PATH
else # ==================================================================
  
  # https://aws.amazon.com/blogs/aws/amazon-ec2-instance-metadata-service-imdsv2-by-default/
  IMDS_TOKEN="$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")"
  [[ -n "${IMDS_TOKEN}" ]] || (echo "error: no IMDS token obtained from http://169.254.169.254/latest/api/token" && exit 1) 
  echo "$(date) ($(whoami)): Attempting join..."
  # Check if user-data exists
  if [[ 
    "$(curl -o /dev/null -s -w "%{http_code}" http://169.254.169.254/latest/user-data -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}")" != "200" || \
    -z "$(curl -s http://169.254.169.254/latest/user-data -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" | grep "ANKA_")" 
  ]]; then
    echo "Could not find any user-data for instance..."
    disjoin || true
    exit
  fi
  sudo sed -i '' "/anka.registry/d" /etc/hosts # Remove hosts modifications for automation (INTERNAL ONLY)  
  # create user ENVs for this session
  eval "$(curl -s http://169.254.169.254/latest/user-data -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" | grep "ANKA_" | grep -v "^#")" # eval needed to handle quotes wrapping ARGS ENV
  # pull latest scripts and restart script
  if [[ -n "${ANKA_PULL_LATEST_CLOUD_CONNECT}" ]]; then
    sudo chown ec2-user:staff /Users/ec2-user/aws-ec2-mac-amis/.git/FETCH_HEAD || true
    git config --global --add safe.directory /Users/ec2-user/aws-ec2-mac-amis
    git fetch
    if [[ ! $(git rev-parse HEAD) == $(git rev-parse @{u}) ]]; then # Ensure we don't restart the script if there aren't any changes.
      git pull
      echo "restarting script now that changes have been made"
      exit 1
    fi
  fi
  # run one of the scripts
  if [[ -n "${ANKA_EXECUTE_SCRIPT}" ]]; then
    ./scripts/${ANKA_EXECUTE_SCRIPT} || true
  fi
  # install latest anka CLI version
  if ${ANKA_UPGRADE_CLI_TO_LATEST:-false}; then
    FULL_FILE_NAME="$(curl -Ls -r 0-1 -o /dev/null -w %{url_effective} https://veertu.com/downloads/anka-virtualization-latest | cut -d/ -f5)"
    if [[ ! -e ./$FULL_FILE_NAME ]]; then 
      curl -S -L -o ./$FULL_FILE_NAME https://veertu.com/downloads/anka-virtualization-latest
      sudo installer -pkg $FULL_FILE_NAME -tgt /
    fi
  fi
  if [[ -n "${ANKA_UPGRADE_CLI_TO_VERSION}" ]]; then
    FULL_FILE_NAME="Anka-${ANKA_UPGRADE_CLI_TO_VERSION}.pkg"
    if [[ ! -e ./$FULL_FILE_NAME ]]; then 
      curl -S -L -o ./$FULL_FILE_NAME https://downloads.veertu.com/anka/$FULL_FILE_NAME
      sudo installer -pkg $FULL_FILE_NAME -tgt /
    fi
  fi
  if ${ANKA_ROUTE_METADATA_TO_VMS:-false}; then
    networksetup -setadditionalroutes Ethernet 169.254.169.254 255.255.255.255 $(sudo defaults read /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist Shared_Net_Address)
  fi
  INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}")"
  INSTANCE_PRIVATE_IP="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}")"
  INSTANCE_PUBLIC_IP="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}")"
  # IF the user wants to change the IP address for the registry domain name (if they want to use a second EC2 registry for better speed), handle setting the /etc/hosts
  if [[ -n "${ANKA_REGISTRY_OVERRIDE_IP}" && -n "${ANKA_REGISTRY_OVERRIDE_DOMAIN}" ]]; then
    modify_hosts $ANKA_REGISTRY_OVERRIDE_DOMAIN $ANKA_REGISTRY_OVERRIDE_IP
  fi

  # Certificate support
  ANKA_CONTROLLER_API_CERTS="${ANKA_CONTROLLER_API_CERTS:-""}"
  if [[ -z "${ANKA_CONTROLLER_API_CERTS}" && -n "${ANKA_CONTROLLER_API_CERT}" ]]; then
    ANKA_CONTROLLER_API_CERTS="--cert ${ANKA_CONTROLLER_API_CERT}"
    if [[ -n "${ANKA_CONTROLLER_API_KEY}" ]]; then
      ANKA_CONTROLLER_API_CERTS="${ANKA_CONTROLLER_API_CERTS} --key ${ANKA_CONTROLLER_API_KEY}"
    else
      echo "missing controller cert key" && exit 2
    fi
    [[ -n "${ANKA_CONTROLLER_API_CA}" ]] && ANKA_CONTROLLER_API_CERTS="${ANKA_CONTROLLER_API_CERTS} --cacert ${ANKA_CONTROLLER_API_CA}"
  fi
  if [[ -n "${ANKA_CONTROLLER_API_CERTS}" ]]; then
    ANKA_CONTROLLER_API_AUTH="${ANKA_CONTROLLER_API_CERTS}"
    # Get registry URL
    ANKA_CONTROLLER_CONFIG_REGISTRY_ADDRESS="$(do_curl -s ${ANKA_CONTROLLER_API_AUTH} ${ANKA_CONTROLLER_ADDRESS}/api/v1/status | jq -r '.body.registry_address')"
  fi

  ANKA_REGISTRY_API_CERTS="${ANKA_REGISTRY_API_CERTS:-""}"
  if [[ -z "${ANKA_REGISTRY_API_CERTS}" && -n "${ANKA_REGISTRY_API_CERT}" ]]; then
    ANKA_REGISTRY_API_CERTS="--cert ${ANKA_REGISTRY_API_CERT}"
    if [[ -n "${ANKA_REGISTRY_API_KEY}" ]]; then
      ANKA_REGISTRY_API_CERTS="${ANKA_REGISTRY_API_CERTS} --key ${ANKA_REGISTRY_API_KEY}"
    else
      echo "missing registry cert key" && exit 2
    fi
    [[ -n "${ANKA_REGISTRY_API_CA}" ]] && ANKA_REGISTRY_API_CERTS="${ANKA_REGISTRY_API_CERTS} --cacert ${ANKA_REGISTRY_API_CA}"
  fi
  if [[ -n "${ANKA_REGISTRY_API_CERTS}" ]]; then
    ANKA_REGISTRY_API_AUTH="${ANKA_REGISTRY_API_CERTS}"
  fi

  # UAK support
  ANKA_CONTROLLER_API_AUTHORIZATION_BEARER="${ANKA_CONTROLLER_API_AUTHORIZATION_BEARER:-""}"
  if [[ -z "${ANKA_CONTROLLER_API_AUTHORIZATION_BEARER}" && -n "${ANKA_CONTROLLER_API_UAK_ID}" ]]; then
    if [[ -z "${ANKA_CONTROLLER_API_UAK_STRING}" ]]; then
      if [[ -z "${ANKA_CONTROLLER_API_UAK_FILE_PATH}" ]]; then
        echo "missing controller uak string or path to pem file" && exit 2
      else
        do_tap ${ANKA_CONTROLLER_ADDRESS} ${ANKA_CONTROLLER_API_UAK_ID} ${ANKA_CONTROLLER_API_UAK_FILE_PATH} ANKA_CONTROLLER_API_AUTHORIZATION_BEARER
      fi
    else
      echo "${ANKA_CONTROLLER_API_UAK_STRING}" | base64 --decode > /tmp/controller-uak-encrypted.pem
      openssl rsa -in /tmp/controller-uak-encrypted.pem --out /tmp/controller-uak-decrypted.pem
      do_tap ${ANKA_CONTROLLER_ADDRESS} ${ANKA_CONTROLLER_API_UAK_ID} /tmp/controller-uak-decrypted.pem ANKA_CONTROLLER_API_AUTHORIZATION_BEARER
    fi
  fi
  if [[ -n "${ANKA_CONTROLLER_API_AUTHORIZATION_BEARER}" ]]; then
    ANKA_CONTROLLER_API_AUTH="${ANKA_CONTROLLER_API_AUTHORIZATION_BEARER}"  
    # Get registry URL
    ANKA_CONTROLLER_CONFIG_REGISTRY_ADDRESS="$(do_curl -s ${ANKA_CONTROLLER_API_AUTH} ${ANKA_CONTROLLER_ADDRESS}/api/v1/status | jq -r '.body.registry_address')"
  fi

  ANKA_REGISTRY_API_AUTHORIZATION_BEARER="${ANKA_REGISTRY_API_AUTHORIZATION_BEARER:-""}"
  if [[ -z "${ANKA_REGISTRY_API_AUTHORIZATION_BEARER}" && -n "${ANKA_REGISTRY_API_UAK_ID}" ]]; then
    if [[ -z "${ANKA_REGISTRY_API_UAK_STRING}" ]]; then
      if [[ -z "${ANKA_REGISTRY_API_UAK_FILE_PATH}" ]]; then
        echo "missing registry uak string or path to pem file" && exit 2
      else
        do_tap ${ANKA_CONTROLLER_CONFIG_REGISTRY_ADDRESS} ${ANKA_REGISTRY_API_UAK_ID} ${ANKA_REGISTRY_API_UAK_FILE_PATH} ANKA_REGISTRY_API_AUTHORIZATION_BEARER
      fi
    else
      echo "${ANKA_REGISTRY_API_UAK_STRING}" | base64 --decode > /tmp/registry-uak-encrypted.pem
      openssl rsa -in /tmp/registry-uak-encrypted.pem --out /tmp/registry-uak-decrypted.pem
      do_tap ${ANKA_CONTROLLER_CONFIG_REGISTRY_ADDRESS} ${ANKA_REGISTRY_API_UAK_ID} /tmp/registry-uak-decrypted.pem ANKA_REGISTRY_API_AUTHORIZATION_BEARER
    fi
  fi

  if [[ -n "${ANKA_REGISTRY_API_AUTHORIZATION_BEARER}" ]]; then
    ANKA_REGISTRY_API_AUTH="${ANKA_REGISTRY_API_AUTHORIZATION_BEARER}"
  fi

  # Always upgrade to the proper agent version first, to support drain-mode and other newer flags/options
  CURRENT_CONTROLLER_VERSION="$(do_curl -s ${ANKA_CONTROLLER_API_AUTH} "${ANKA_CONTROLLER_ADDRESS}/api/v1/status" | jq -r '.body.version' | cut -d- -f1 | sed 's/\.//g')"
  [[ "${CURRENT_CONTROLLER_VERSION}" == "null" ]] && { echo "error: unable to get controller version" && exit 1; }
  if [[ "${CURRENT_CONTROLLER_VERSION}" -gt $(ankacluster --version | cut -d- -f1 | sed 's/\.//g') ]]; then
    do_curl -O ${ANKA_CONTROLLER_API_AUTH} "${ANKA_CONTROLLER_ADDRESS}/pkg/${AGENT_PKG_NAME}"
    installer -pkg ${AGENT_PKG_NAME} -tgt /
  fi

  # Join arguments
  ANKA_JOIN_ARGS="${ANKA_JOIN_ARGS:-"$*"}" # used for older getting started script + enables overriding defaults from inside plist instead of user-data
  if sudo ankacluster join --help | grep "node-id"; then # make sure we don't try to join with --node-id unless it's an available option for ankacluster
    [[ ! "${ANKA_JOIN_ARGS}" =~ "--node-id" ]] && ANKA_JOIN_ARGS="${ANKA_JOIN_ARGS} --node-id ${INSTANCE_ID}"
  fi
  HARDWARE_TYPE="$(system_profiler SPHardwareDataType | grep 'Hardware UUID' | awk '{print $NF}')"
  # removed in 13.0.1/3.2.0 as not having enough space for the VMs to use can be a problem
  # [[ ! "${ANKA_JOIN_ARGS}" =~ "--reserve-space" ]] && ANKA_JOIN_ARGS="${ANKA_JOIN_ARGS} --reserve-space $(df -H | grep /dev/ | head -1 | awk '{print $4}')B"
  ${ANKA_USE_PUBLIC_IP:-false} && INSTANCE_IP="${INSTANCE_PUBLIC_IP}" || INSTANCE_IP="${INSTANCE_PRIVATE_IP}"
  [[ ! "${ANKA_JOIN_ARGS}" =~ "--host" ]] && ANKA_JOIN_ARGS="${ANKA_JOIN_ARGS} --host ${INSTANCE_IP}"

  # check if certs are even needed; throw error if user didn't include them
  if [[ "$(do_curl -s "${ANKA_CONTROLLER_ADDRESS}/api/v1/status" | jq '.message')" == "Authentication Required" ]]; then
    if [[ -z "${ANKA_CONTROLLER_API_CERTS}" && -z "${ANKA_CONTROLLER_API_AUTHORIZATION_BEARER}" ]]; then
      echo "missing controller certs or uak" && exit 2
    fi
  fi
  if [[ "$(do_curl -s "${ANKA_CONTROLLER_CONFIG_REGISTRY_ADDRESS}/registry/status" | jq '.message')" == "Authentication Required" ]]; then
    if [[ -z "${ANKA_REGISTRY_API_CERTS}" && -z "${ANKA_REGISTRY_API_AUTHORIZATION_BEARER}" ]]; then
      echo "missing registry certs or uak" && exit 2
    fi
  fi
  
  # Handle license
  anka license accept-eula 2>/dev/null || true
  if [[ -n "${ANKA_LICENSE}" ]]; then # Activate license if present
    anka license show
    if ! anka --machine-readable license show | grep 'status": "valid"'; then
      echo "Activating anka license..."
      ANKA_LICENSE_ACTIVATE_STDOUT="$(anka license activate -f "${ANKA_LICENSE}" || true)"
      echo "${ANKA_LICENSE_ACTIVATE_STDOUT}"
      # Post the fulfillment ID to the centralized logs
      do_curl ${ANKA_REGISTRY_API_AUTH} -v "${ANKA_CONTROLLER_CONFIG_REGISTRY_ADDRESS}/log" -d "{\"machine_name\": \"${INSTANCE_ID} | ${HARDWARE_TYPE}\", \"service\": \"AWS Cloud Connect Service\", \"host\": \"\", \"content\": \"${ANKA_LICENSE_ACTIVATE_STDOUT}\"}"
    fi
    anka license show
  fi

  /usr/local/bin/ankacluster disjoin || true

  ${ANKA_DRAINED_ON_JOIN:-false} && ANKA_JOIN_ARGS="${ANKA_JOIN_ARGS} --drain-mode"
  
  if [[ -n "${ANKA_PULL_TEMPLATES_REGEX}" ]]; then
    TEMPLATES_TO_PULL=()
    TEMPLATES_TO_PULL+=($(do_curl -s ${ANKA_REGISTRY_API_AUTH} "${ANKA_CONTROLLER_CONFIG_REGISTRY_ADDRESS}/registry/vm" | jq -r '.body[] | keys[]' | grep -E "${ANKA_PULL_TEMPLATES_REGEX}" || true))
    TEMPLATES_TO_PULL+=($(do_curl -s ${ANKA_REGISTRY_API_AUTH} "${ANKA_CONTROLLER_CONFIG_REGISTRY_ADDRESS}/registry/vm" | jq -r '.body[] | values[]' | grep -E "${ANKA_PULL_TEMPLATES_REGEX}" || true))
    echo "${TEMPLATES_TO_PULL[@]}"
    if ${ANKA_PULL_TEMPLATES_REGEX_DISTRIBUTE:-false}; then
        /usr/local/bin/ankacluster join ${ANKA_CONTROLLER_ADDRESS} ${ANKA_JOIN_ARGS}
    fi
    for TEMPLATE_NAME in "${TEMPLATES_TO_PULL[@]}"; do
      if ${ANKA_PULL_TEMPLATES_REGEX_DISTRIBUTE:-false}; then
        TEMPLATE_ID=$(do_curl -s ${ANKA_CONTROLLER_API_AUTH} "${ANKA_CONTROLLER_ADDRESS}/api/v1/registry/vm" | jq -r ".body[] | select(.name == \"$TEMPLATE_NAME\") | .id" || true)
        DISTRIBUTION_ID="$(do_curl -X POST -s ${ANKA_CONTROLLER_API_AUTH} "${ANKA_CONTROLLER_ADDRESS}/api/v1/registry/vm/distribute" -d "{\"template_id\": \"${TEMPLATE_ID}\", \"node_ids\": [\"${INSTANCE_ID}\"]}" | jq -r '.body.request_id' || true)"
        sleep 2
        if [[ $(do_curl -s ${ANKA_CONTROLLER_API_AUTH} "${ANKA_CONTROLLER_ADDRESS}/api/v1/registry/vm/distribute?id=${DISTRIBUTION_ID}" | jq -r ".body.distribute_status[\"${INSTANCE_ID}\"] | .status") == "null" ]]; then
          echo "Distribution failed; unable to get status of distribution"
          exit 1
        fi
        while [[ "$(do_curl -s ${ANKA_CONTROLLER_API_AUTH} "${ANKA_CONTROLLER_ADDRESS}/api/v1/registry/vm/distribute?id=${DISTRIBUTION_ID}" | jq -r ".body.distribute_status[\"${INSTANCE_ID}\"] | .status")" != "true" ]]; do
          sleep 10
        done
      else
        anka --debug registry -r "${ANKA_CONTROLLER_CONFIG_REGISTRY_ADDRESS}" pull "${TEMPLATE}"
      fi
    done
    if ${ANKA_PULL_TEMPLATES_REGEX_DISTRIBUTE:-false}; then
      do_curl -X POST ${ANKA_CONTROLLER_API_AUTH} "${ANKA_CONTROLLER_ADDRESS}/api/v1/node/config" -d "{\"node_id\": \"${INSTANCE_ID}\", \"drain_mode\": false}"
    fi
  fi
  sleep 10 # AWS instances, on first start, and even with functional networking (we ping github.com above), will have 169.254.169.254 assigned to the default interface and since joining happens very early in the startup process, that'll be what is assigned in the controller and cause problems.

  if ! ${ANKA_PULL_TEMPLATES_REGEX_DISTRIBUTE:-false}; then
    /usr/local/bin/ankacluster join ${ANKA_CONTROLLER_ADDRESS} ${ANKA_JOIN_ARGS}
  fi
  # Do a quick check to see if there was a problem post-start
  sleep 3
  ankacluster status
  tail -50 /var/log/veertu/anka_agent.ERROR || true
  [[ -n "$(ankacluster status | grep "not running" || true)" ]] && exit 1
  touch "${CLOUD_CONNECT_JOINED_FILE}" # create file that indicates whether cloud-connect joined to the controller or not using userdata so that we don't disjoin manually joined users.
  trap disjoin 0 # Disjoin after we joined properly to avoid unloading prematurely
  set +x
  echo "Joined and now we'll stay alive and wait for a shutdown signal..."
  mkfifo /tmp/wait-fifo; read < /tmp/wait-fifo
fi
