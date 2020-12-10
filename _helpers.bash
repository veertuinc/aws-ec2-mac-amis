LAUNCH_LOCATION="/Library/LaunchDaemons/"
CLOUD_CONNECT_PLIST_PATH="${LAUNCH_LOCATION}com.veertu.aws-ec2-mac-amis.cloud-connect.plist"
RESIZE_DISK_PLIST_PATH="${LAUNCH_LOCATION}com.veertu.aws-ec2-mac-amis.resize-disk.plist"

# Check if user-data exists
[[ ! -z "$(curl -s http://169.254.169.254/latest/user-data | grep 404)" ]] && echo "Could not find required ANKA_CONTROLLER_ADDRESS in instance user-data!" && exit 1

modify_hosts() {
  [[ -z $1 ]] && echo "ARG 1 missing" && exit 1
  [[ -z $1 ]] && echo "ARG 2 missing" && exit 1
  SED="sudo sed -i ''"
  HOSTS_LOCATION="/etc/hosts"
  $SED "/$1/d" $HOSTS_LOCATION
  echo "$2 $1" | sudo tee -a $HOSTS_LOCATION
}

true