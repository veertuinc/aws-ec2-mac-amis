LAUNCH_LOCATION="/Library/LaunchDaemons/"
CLOUD_CONNECT_PLIST_PATH="${LAUNCH_LOCATION}com.veertu.aws-ec2-mac-amis.cloud-connect.plist"
RESIZE_DISK_PLIST_PATH="${LAUNCH_LOCATION}com.veertu.aws-ec2-mac-amis.resize-disk.plist"

# Check if user-data exists
[[ ! -z "$(curl -s http://169.254.169.254/latest/user-data | grep 404)" ]] && echo "Could not find required ANKA_CONTROLLER_ADDRESS in instance user-data!" && exit 1

true