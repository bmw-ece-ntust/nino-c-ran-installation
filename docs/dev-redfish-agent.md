# Remote Installation and Provisioning of OS

This module aims to perform OS installation on COTS server with Redfish supported BMC.
This module will be part of O2 e2e module for remote installation from Day-0 of O-Cloud clusters.

## Prerequisites

### Setup Nginx

Goals:
1. Create NGINX instance to host ISO
2. Upload your generated iso to that NGINX instance. Use scp or anything.

#### Host image on docker

```bash
.
├── docker-compose.yaml
├── nginx-iso
│   └── isos
│       ├── kickstart
│       │   └── default.ks
│       ├── rhel
│       │   └── 9.5
│       ├── rhel-9.5-kickstart.iso
│       ├── rhel-9.5-x86_64-boot.iso
│       ├── template-coreos-live-iso.x86_64.iso
│       └── ubuntu-22.04-latest-live-server-amd64.iso
└── nginx.conf
```


1. Create directories ISOs and Kickstart

```bash
mkdir -p nginx-iso/isos/kickstart
mkdir -p nginx-iso/isos/rhel
```

2. `docker-compose.yaml`

    ```yaml
    version: '3'

    services:
      nginx-iso:
        image: docker.io/nginx:alpine
        ports:
          - "3001:80"
        volumes:
          - ./nginx.conf:/etc/nginx/conf.d/default.conf:Z
          - ./nginx-iso/isos:/usr/share/nginx/html/isos:Z
        restart: unless-stopped
    ```

2. `nginx.conf`

    ```nginx
    server {
        listen 80;
        server_name 192.168.8.75;

        location /isos/ {
            alias /usr/share/nginx/html/isos/;
            autoindex on;
            autoindex_exact_size off;
            autoindex_localtime on;
        }

        location / {
            return 301 /isos/;
        }
    }
    ```

3. Start the container instance

    ```bash
    podman-compose up -d
    ```
4. Validate the servic is up, make sure you got HTTP 200 as reponse

    ```bash
    curl http://<Machine-IP>:3001/isos/
    ```

### Create Kickstart template

You need to define the following parameters appropriately

1. `<NGINX-HOST>` : IP or DNS name of the nginx instance where you put your ISOs
2. `<TARGET_HOSTNAME>` : Temporary hostname during installation
3. `<TARGET_ROOT_PASSWORD>` : This will be your root password, you can generate it using `openssl` command. Refer to the example here;

    ```bash
    openssl passwd -6 -salt randomsalt123 hellopassword

    # Output
    $6$randomsalt123$vvD4nCAr6K7xyY83sB0I3dmW7OVUOfZfvdA6r3DLotXgMjK4CywjjAtOu/kRcGtcTTcCtMetC4rCkHi.1AhDI1
    ```
4. `<YOUR_SSH_KEY>` : This will allow you to access the target machines via SSH without password. This will be useful for next steps of automatic provisioning, as by doing this later on you can let your ansible instance to remotely run command on the target machine. Refer to the next example:
    ```bash
    # Create new SSH pubkey on Linux or MacOS. No passphrase.
    ssh-keygen -t ed25519 -f .ssh/provision_key -N ''

    # YOUR_SSH_KEY content will be the content inside provision_key.pub file
    cat .ssh/provision_key.pub
    ```

5. Populate the follwing template with values from previous steps.

> [!WARNING]
> This will overwrite and reinstall any targeted server without any regards of previous installation so please youse with cas

```ks

# rhel9-rt.ks
#version=RHEL9
authselect select sssd

# This is your NGINX instance
url --url="http://<NGINX-HOST>:3001/isos/rhel/9.5/"
text
keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8
network --bootproto=dhcp --device=link --hostname=< --activate
rootpw --iscrypted <TARGET_ROOT_PASSWORD>
selinux --enforcing
services --enabled="chronyd,sshd,NetworkManager"
timezone UTC --utc

# FIXED DISK CONFIGURATION
clearpart --all --initlabel

# Explicit partitioning for reliable boot (works for both BIOS and UEFI)
part /boot/efi --fstype=efi --size=256 --ondisk=sda --asprimary
part /boot --fstype=xfs --size=1024 --ondisk=sda --asprimary
part pv.01 --size=1 --grow --ondisk=sda --asprimary
volgroup rhel pv.01
logvol / --fstype=xfs --name=root --vgname=rhel --size=1 --grow
logvol swap --fstype=swap --name=swap --vgname=rhel --size=8192

# FIXED BOOTLOADER - auto-detect boot drive
bootloader --location=mbr

%packages
@^minimal-environment
@core
grub2-efi-x64
grub2-efi-x64-modules
shim-x64
efibootmgr
%end

%post --nochroot --log=/mnt/sysimage/root/ks-post.log

mkdir -p /mnt/sysimage/root/.ssh
cat >> /mnt/sysimage/root/.ssh/authorized_keys << 'SSHKEY'
<YOUR_SSH_KEY>
SSHKEY
chmod 600 /mnt/sysimage/root/.ssh/authorized_keys

%end

reboot --eject

```

### Inject RHEL ISO with Kickstart script

To perform fully automated installation you need to inject the RHEL ISO with previous kickstart files so the installation will be performed fully without human intervention.

1. Download RHEL ISO
2. Define the follwoing parameters on `script/inject.sh`
    ```
    ORIGINAL_ISO="<WHERE_YOU_PUT_YOUR_ISO>/rhel-9.5-x86_64-boot.iso" # Original ISo
    OUTPUT_ISO="rhel-9.5-kickstart.iso" # Your Result ISO
    HTTP_SERVER="<NGINX_HOST_IP>:3001"
    KICKSTART_PATH="isos/kickstart/default.ks" # Kickstart script path on NGINX
    ```
3. Run `script/inject.sh`

If it succeess you shold have your template iso now



### Upload ISO and Kickstart

For fully offline installation you can also host your BaseOS content on the Nginx instance. This way the nodes wont have to connected to internet (Only the provisioner), this will also skip the redhat registarion phase on the during installation (We will register upoin OS provision)

1. Extract DVD ISO
2. Upload DVD ISO contents to NGINX instance at `<NGINX_DIR>/nginx-isos/isos/rhel/`
3. Upload kickstart template to `<NGINX_DIR>/nginx-isos/isos/kickstart/`
4. Upload template ISO to `<NGINX_DIR>/nginx-isos/isos/rhel-9.5-kickstart.ios`

## Provisioning

### Machine Declarations

Declare your machine in the following manner

```yaml
log_level: INFO
redfish_timeout: 30
ssh_timeout: 1800
wait_for_ssh: true
install_delay: 60  # seconds between installations
parallel_installation: false

# Server configurations
servers:
  - name: worker-rt-00 # Unique name of this instance
    idrac_host: 192.168.10.XXX # BMC_IP
    idrac_user: <IDRAC_USER>
    idrac_pass: <IDRAC_PASS>
    target_host: 192.168.8.74 # IP of the Machine
    #iso_url: http://192.168.1.10/iso/rhel-9.4-rt-kickstart.iso
    iso_url: http://192.168.8.75:3001/isos/rhel-9.5-kickstart.iso # Where we host our ISO
    mac_address: ""

  - name: worker-rt-01
    idrac_host: 192.168.10.XXX
    idrac_user: <IDRAC_USER>
    cidrac_pass: <IDRAC_PASS>
    ,target_host: 192.168.8.123 # IP of the Machine,
    #iso_url: http://192.168.1.10/iso/rhel-9.4-rt-kickstart.iso
    iso_url: http://192.168.8.75:3001/isos/rhel-9.5-kickstart.iso
    mac_address: ""

```
