PATH=/usr/local/bin:$PATH # /Users/ec2-user/aws-ec2-mac-amis/cloud-connect.bash: line 17: jq: command not found
LAUNCH_LOCATION="/Library/LaunchDaemons/"; mkdir -p "${LAUNCH_LOCATION}";
AWS_INSTANCE_USER="ec2-user"
# AWS_INSTANCE_USER_PASSWD="zbun0ok=" # This will eventually go away. It's only required because dscl enables Secure Token for ec2-user after first run (first run doesn't need an old password; passwd also does this) # no need since we can't VNC anymore
RESIZE_DISK_PLIST_PATH="${LAUNCH_LOCATION}com.veertu.aws-ec2-mac-amis.resize-disk.plist"
CLOUD_CONNECT_PLIST_PATH="${LAUNCH_LOCATION}com.veertu.aws-ec2-mac-amis.cloud-connect.plist"

ARCH="$(arch)"
[[ "${ARCH}" != "arm64" ]] && ARCH="amd64"

# get agent package name
[[ ${ARCH} == "arm64" ]] && AGENT_PKG_NAME="AnkaAgentArm.pkg" || AGENT_PKG_NAME="AnkaAgent.pkg"

modify_hosts() {
  [[ -z $1 ]] && echo "ARG 1 missing" && exit 1
  [[ -z $1 ]] && echo "ARG 2 missing" && exit 1
  SED="sudo sed -i ''"
  HOSTS_LOCATION="/etc/hosts"
  $SED "/$1/d" $HOSTS_LOCATION
  echo "$2 $1" | sudo tee -a $HOSTS_LOCATION
}

do_tap() {
  [[ -z $1 ]] && echo "ARG 1 (url) is required" && exit 1
  URL=$1
  [[ -z $2 ]] && echo "ARG 2 (id) is required" && exit 1
  UAK_ID=$2
  [[ -z $3 ]] && echo "ARG 3 (pem file path) is required" && exit 1
  UAK_SECRET_PEM_PATH=$3
  [[ -z $4 ]] && echo "ARG 4 (output variable name) is required" && exit 1
  OUTPUT_VARIABLE_NAME=$4
  trap 'rm -f "$UAK_SECRET_PEM_PATH"' EXIT
  echo -n $(curl -s ${URL}/tap/v1/hand -d "{\"id\": \"${UAK_ID}\"}") | base64 -d > /tmp/to_decrypt
  openssl pkeyutl -decrypt -inkey ${UAK_SECRET_PEM_PATH} -in /tmp/to_decrypt -out /tmp/decrypted -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256
  SHAKE_RESPONSE=$(curl -s ${URL}/tap/v1/shake -d "{\"id\": \"${UAK_ID}\", \"secret\": \"$(cat /tmp/decrypted)\" }")
  ACCESS_TOKEN=$(echo "${SHAKE_RESPONSE}" | jq -r '.data' | base64)
  if [[ $(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${ACCESS_TOKEN}" ${URL}/api/v1/status) != "200" ]]; then
    if [[ $(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${ACCESS_TOKEN}" ${URL}/registry/status) != "200" ]]; then
      echo "Failed to authenticate with ${URL}"
      exit 1
    fi
  fi
  eval "${OUTPUT_VARIABLE_NAME}=\"-H 'Authorization: Bearer ${ACCESS_TOKEN}'\""
}

do_curl() {
  # we need to eval or else UAK Authorizaton Bearer will have broken quotes
  eval curl "$@"
}

configure_uak() {
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
}

true