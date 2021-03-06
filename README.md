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

1. `cd /Users/ec2-user && git clone https://github.com/veertuinc/aws-ec2-mac-amis.git && cd aws-ec2-mac-amis && ANKA_LICENSE="XXX" ./$(sw_vers | grep ProductVersion | cut -d: -f2 | xargs)/prepare.bash`
2. Resizing of the disk may take a while. The instance may seem stuck, so be patient and only create the AMI once it's done (check `/var/log/resize-disk.log` to confirm)
3. Set password with `sudo /usr/bin/dscl . -passwd /Users/ec2-user {NEWPASSWORDHERE}`. Once set, you can setup auto-login:
    ```bash
    git clone https://github.com/veertuinc/kcpassword.git
    cd kcpassword
    ./enable_autologin "ec2-user" "{GENERATEDPASSWORD}"
    ```
4. You now need to VNC in once (requirement for Anka to have necessary services): `open vnc://ec2-user:{GENERATEDPASSWORD}@{INSTANCEPUBLICIP}`
5. Once in VNC, Go to Preferences > Security > under General > uncheck `require password after screensave or sleep begins` option.

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


## Usage of AMI

> **IMPORTANT:** Amazon confirmed that Terminating from the AWS console/API does not properly send SIGTERMs to services and wait for them to stop. This prevents the joined-to-cloud EC2 Instance from disjoining `ankacluster disjoin`. Therefore, we recommend sending a `SIGTERM` or `sudo launchctl unload -w /Library/LaunchDaemons/com.veertu.aws-ec2-mac-amis.cloud-connect.plist` command before termination of the instance. The best place for this is at the end of a successful CI/CD build.

## Prepare an Instance

```bash
aws ec2 allocate-hosts --availability-zone "us-west-2a" --auto-placement "on" --host-recovery "off" --quantity 1 --instance-type "mac1.metal"
```

Note: Dedicated requests can take a while

Request an instance on the dedicated with:

> For user-data, don't use `;`, `&&` or any other type of separator between envs (see example below for format for ENVs)

```bash
aws ec2 run-instances --image-id ami-04bf95d5a9cd66285 --instance-type mac1.metal --placement "HostId={HOSTIDHERE}" --key-name aws-veertu --ebs-optimized --associate-public-ip-address --security-group-ids sg-0893eeb7c6cae6da4 --user-data "export ANKA_CONTROLLER_ADDRESS=\"http://{CONTROLLER/REGISTRYIP}:8090\" export ANKA_REGISTRY_OVERRIDE_IP=\"{CONTROLLER/REGISTRYIP}\" export ANKA_REGISTRY_OVERRIDE_DOMAIN=\"anka.registry\"" --count 1 --block-device-mappings '[{ "DeviceName": "/dev/sda1", "Ebs": { "VolumeSize": 400, "VolumeType": "gp3" }}]'
```

After your CI/CD builds/tests complete, and before the EC2 Instance is terminated, you'll need to execute `sudo launchctl unload -w  /Library/LaunchDaemons/com.veertu.aws-ec2-mac-amis.cloud-connect.plist`. This unload will disjoin the node from the controller. Otherwise, you'll see nodes being orphaned as "Offline", requiring manual deletion with the API.