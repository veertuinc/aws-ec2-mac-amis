LAUNCH_LOCATION="/Library/LaunchDaemons/"
CLOUD_CONNECT_PLIST_PATH="${LAUNCH_LOCATION}com.veertu.aws-ec2-mac-amis.cloud-connect.plist"
RESIZE_DISK_PLIST_PATH="${LAUNCH_LOCATION}com.veertu.aws-ec2-mac-amis.resize-disk.plist"
PATH=/usr/local/bin:$PATH # /Users/ec2-user/aws-ec2-mac-amis/cloud-connect.bash: line 17: jq: command not found
AWS_INSTANCE_USER="ec2-user"

modify_hosts() {
  [[ -z $1 ]] && echo "ARG 1 missing" && exit 1
  [[ -z $1 ]] && echo "ARG 2 missing" && exit 1
  SED="sudo sed -i ''"
  HOSTS_LOCATION="/etc/hosts"
  $SED "/$1/d" $HOSTS_LOCATION
  echo "$2 $1" | sudo tee -a $HOSTS_LOCATION
}

true