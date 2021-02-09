# Veertu's AWS EC2 AMI scripts and instructions

All AMIs are built from the default AWS AMIs.
> The macOS Catalina AMI is an EBS-backed, AWS-supported image. This AMI includes the AWS Command Line Interface, Command Line Tools for Xcode, Amazon SSM Agent, and Homebrew. The AWS Homebrew Tap includes the latest versions of multiple AWS packages included in the AMI.
>
> Root device type: ebs | Virtualization type: hvm | ENA Enabled: Yes


What we add, regardless of macOS version:

- [`anka virtualization`](https://veertu.com/anka-build/)
- [`jq`](https://formulae.brew.sh/formula/jq) : Lightweight and flexible command-line JSON processor
- `ll` alias to `ls -laht`
- [`ec2-metadata`](https://aws.amazon.com/code/ec2-instance-metadata-query-tool/)

## Prepare an AMI

1. `cd /Users/ec2-user && git clone https://github.com/veertuinc/aws-ec2-mac-amis.git && cd aws-ec2-mac-amis && ANKA_LICENSE="XXX" ./10.15.7/prepare.bash`
3. Resizing of the disk may take a while. The instance may seem stuck, so be patient and only create the AMI once it's done (check `/var/log/resize-disk.log` to confirm)

This should install everything you need (the script is indempotent). You can then sanity check and then save the AMI.

## Logs

- `/var/log/resize-disk.log`
- `/var/log/cloud-connect.log`
## Environment variables you pass in as `user-data`

#### **ANKA_CONTROLLER_ADDRESS**
- **REQUIRED**
- Must be in the following structure: `http[s]://[IP/DOMAIN]:[PORT]`

#### **ANKA_JOIN_ARGS**
- Optional
- Allows you to pass in any "Flags" from `ankacluster join --help`

#### **ANKA_REGISTRY_OVERRIDE_IP** + **ANKA_REGISTRY_OVERRIDE_DOMAIN**
Allows you to set the registry IP address and domain in the `/etc/hosts` file
- Optional
- Use 1: if your corporate registry doesn't have a public domain name, but does have a public IP
- Use 2: if you want the EC2 mac mini to pull from a second registry that's hosted on EC2 instead of a local corporate one (AWS -> AWS is much faster)


## Usage

> **IMPORTANT:** Amazon confirmed that Terminating from the AWS console/API does not properly send SIGTERMs to services and wait for them to stop. This prevents the joined-to-cloud EC2 Instance from disjoining `ankacluster disjoin`. Therefore, we recommend sending a `SIGTERM` or `sudo launchctl unload -w /Library/LaunchDaemons/com.veertu.aws-ec2-mac-amis.cloud-connect.plist` command before termination of the instance. The best place for this is at the end of a successful CI/CD build.

Request a dedicated with:

```bash
DEDICATED_HOST_ID=$(aws ec2 allocate-hosts --availability-zone "us-west-2a" --auto-placement "on" --host-recovery "off" --quantity 1 --instance-type "mac1.metal" | jq -r ".HostIDs[0]")
while [[ "$(aws ec2 describe-hosts --host-ids $DEDICATED_HOST_ID | jq -r ".Hosts[0].State")" != "available" ]]; do echo "Dedicated Availability is still pending... This can take quite a while sometimes..."; sleep 20; done
echo "Dedicated is available!"
```

Request an instance on the dedicated with:

> For user-data, don't use `;`, `&&` or any other type of separator between envs (see example below for format for ENVs)

```bash
aws ec2 run-instances --image-id ami-04bf95d5a9cd66285 --instance-type mac1.metal --placement "HostId=h-0ae72efe1c1cd2954" --key-name aws-veertu --ebs-optimized --security-group-ids sg-0893eeb7c6cae6da4 --user-data "export ANKA_CONTROLLER_ADDRESS=\"http://18.237.36.178:8090\" export ANKA_REGISTRY_OVERRIDE_IP=\"18.237.36.178\" export ANKA_REGISTRY_OVERRIDE_DOMAIN=\"anka.registry\"" --count 1 --block-device-mappings '[{ "DeviceName": "/dev/sda1", "Ebs": { "VolumeSize": 100 }}]'
```