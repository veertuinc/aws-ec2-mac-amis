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
  curl -sH "Authorization: Bearer ${ACCESS_TOKEN}" ${URL}/api/v1/status
  eval "${OUTPUT_VARIABLE_NAME}=\"-H \"Authorization: Bearer ${ACCESS_TOKEN}\""
}

true