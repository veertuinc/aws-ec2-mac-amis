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

The public AMIs in AWS have these steps already performed inside of them. However, you will likely want to change the password.

1. `cd /Users/ec2-user && git clone https://github.com/veertuinc/aws-ec2-mac-amis.git && cd aws-ec2-mac-amis && ANKA_LICENSE="skip" ./$(sw_vers | grep ProductVersion | cut -d: -f2 | xargs)/prepare.bash`
2. Resizing of the disk may take a while. The instance may seem stuck, so be patient and only create the AMI once it's done (check `/var/log/resize-disk.log` to confirm)
3. You now need to VNC in once (requirement for Anka to have necessary services): `open vnc://ec2-user:{GENERATEDPASSWORD}@{INSTANCEPUBLICIP}`
4. Test `anka create` using generate getting-started scripts + delete VM it creates after starting and running command inside
5. Ensure cloud connect service works with user-data
6. Restart without user-data
7. Remove license `sudo anka license remove`
8. As user **AND** root:

  ```bash
  anka delete --yes --all;
  echo "" | tee /Library/Logs/Anka/anka.log; 
  echo "" | tee /var/log/cloud-connect.log;
  echo "" | tee /var/log/resize-disk.log; 
  rm -f ~/.ssh/authorized_keys; 
  rm -f ~/.*_history; 
  rm -f ~/.bash_history; 
  rm -rf /tmp/anka-mac-resources; 
  rm -rf /Applications/Install*;
  find "$(anka config img_lib_dir)" -mindepth 1 -delete;
  find "$(anka config state_lib_dir)" -mindepth 1 -delete;
  find "$(anka config vm_lib_dir)" -mindepth 1 -delete;
  ```

This should install everything you need (the script is idempotent). You can then sanity check and then save the AMI.

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

#### **ANKA_LICENSE** (only available in 2.5.4 AMIs)
If not already licensed, the cloud-connect service will license Anka using this ENV's value.
- Optional
- You can also update invalid/expired licenses with this.

## Usage of AMI

> **IMPORTANT:** Amazon confirmed that Terminating from the AWS console/API does not properly send SIGTERMs to services and wait for them to stop. This prevents the joined-to-cloud EC2 Instance from disjoining `ankacluster disjoin`. Therefore, we recommend sending a `SIGTERM` or `sudo launchctl unload -w /Library/LaunchDaemons/com.veertu.aws-ec2-mac-amis.cloud-connect.plist` command before termination of the instance. The best place for this is at the end of a successful CI/CD build.

## Prepare an Instance

```bash
aws ec2 allocate-hosts --availability-zone "us-west-2a" --auto-placement "on" --host-recovery "off" --quantity 1 --instance-type "mac1.metal"
```

Note: Dedicated requests can take a while

Request an instance on the dedicated with:

> - For user-data, don't use `;`, `&&` or any other type of separator between envs (see example below for format for ENVs)
> - If you pass in user-data with the exports all on one line, and have non ANKA_ ENVs you're setting, the `cloud-connect.bash` will source/execute them. We recommend you split exports and user-data onto separate lines to avoid this.

```bash
aws ec2 run-instances --image-id {AMI_ID_HERE} --instance-type mac1.metal --placement "HostId={HOSTIDHERE}" --key-name aws-veertu --ebs-optimized --associate-public-ip-address --security-group-ids sg-0893eeb7c6cae6da4 --user-data "export ANKA_CONTROLLER_ADDRESS=\"http://{CONTROLLER/REGISTRYIP}:8090\" export ANKA_REGISTRY_OVERRIDE_IP=\"{CONTROLLER/REGISTRYIP}\" export ANKA_REGISTRY_OVERRIDE_DOMAIN=\"anka.registry\"" --count 1 --block-device-mappings '[{ "DeviceName": "/dev/sda1", "Ebs": { "VolumeSize": 500, "VolumeType": "gp3" }}]'
```

After your CI/CD builds/tests complete, and before the EC2 Instance is terminated, you'll need to execute `sudo launchctl unload -w  /Library/LaunchDaemons/com.veertu.aws-ec2-mac-amis.cloud-connect.plist`. This unload will disjoin the node from the controller. Otherwise, you'll see nodes being orphaned as "Offline", requiring manual deletion with the API.