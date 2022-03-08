# Veertu's AWS EC2 AMI Prep Scripts

All AMIs are built from the default AWS AMIs.

> The macOS AMI is an EBS-backed, AWS-supported image. This AMI includes the AWS Command Line Interface, Command Line Tools for Xcode, Amazon SSM Agent, and Homebrew. The AWS Homebrew Tap includes the latest versions of multiple AWS packages included in the AMI.
>
> Root device type: ebs | Virtualization type: hvm | ENA Enabled: Yes

What we add, regardless of macOS version:

- [`anka virtualization`](https://veertu.com/anka-build/)
- [`jq`](https://formulae.brew.sh/formula/jq) : Lightweight and flexible command-line JSON processor
- `ll` alias to `ls -laht`

## Prepare an AMI

The official Veertu AMIs in AWS have these steps already performed inside of them:

1. `cd /Users/ec2-user && git clone https://github.com/veertuinc/aws-ec2-mac-amis.git && cd aws-ec2-mac-amis && ANKA_LICENSE="skip" ./$(sw_vers | grep ProductVersion | cut -d: -f2 | xargs)/prepare.bash; unset HISTFILE`
1. Resizing of the disk may take a while. The instance may seem stuck, so be patient and only create the AMI once it's done (check `/var/log/resize-disk.log` to confirm)
1. You now need to VNC in once (requirement for Anka to have necessary services): `open vnc://ec2-user:{GENERATEDPASSWORD}@{INSTANCEPUBLICIP}`
1. Test `anka create` using generate getting-started scripts + delete VM it creates after starting and running command inside
1. Ensure cloud connect service works with user-data
1. Restart without user-data
1. As user **AND** root:
    ```bash
    anka registry delete --all;
    anka delete --yes --all;
    echo "" | tee /Library/Logs/Anka/anka.log; 
    echo "" | tee /var/log/cloud-connect.log;
    echo "" | tee /var/log/resize-disk.log; 
    rm -f ~/.ssh/authorized_keys; 
    rm -f ~/.*_history; 
    history -p;
    rm -rf /tmp/anka-mac-resources; 
    rm -rf /Applications/Install*;
    echo 123;
    rm -rf ~/.zsh_*;
    find "$(anka config img_lib_dir)" -mindepth 1 -delete;
    find "$(anka config state_lib_dir)" -mindepth 1 -delete;
    find "$(anka config vm_lib_dir)" -mindepth 1 -delete;
    ```
1. Remove license `sudo anka license remove`
1. **DO NOT LEAVE THE TERMINAL ON VNC OPEN; QUIT THE APP**


This should install everything you need (the script is idempotent). You can then sanity check and then save the AMI.

## Logs

- `/var/log/resize-disk.log`
- `/var/log/cloud-connect.log`

## Usage of AMI

[Please see the documentaion!](https://docs.veertu.com/anka/intel/getting-started/aws-ec2-mac/)