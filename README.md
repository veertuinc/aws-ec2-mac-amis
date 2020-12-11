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

1. `cd /Users/ec2-user && git clone https://github.com/veertuinc/aws-ec2-mac-amis.git`
2. `cd aws-ec2-mac-amis && ANKA_LICENSE="XXX" ./10.15.7/prepare.bash`

This should install everything you need (the script is indempotent). You can then sanity check and then save the AMI.

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



