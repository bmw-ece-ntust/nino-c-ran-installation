# OpenStack Deployment for O2 IMS Testing

![Overall](../assets/O2-IMS-PTI-Development.png)

## Objective
Deploy minimal OpenStack on RHEL 9 for OSC PTI O2 IMS testing and bare metal provisioning via Redfish.

---

## Deployment Progress Tracker

| Task | Status |
|------|--------|
| [Install Centos 9 on controller VM](#11-controller-vm-setup) | ✅ Complete |
| [Install Centos 9 on bare metal compute](#12-compute-node-setup) | ✅ Complete |
| [Configure Podman + compatibility layer](#13-container-runtime) | ✅ Complete |
| [Setup SSH keys and passwordless sudo](#14-access-configuration) | ✅ Complete |
| [Create Python venv and install Kolla](#21-python-environment) | ✅ Complete |
| [Configure inventory and host_vars](#22-inventory-configuration) | ✅ Complete |
| [Configure globals.yml](#23-global-configuration) | ✅ Complete |
| [Download Ironic deploy images](#24-ironic-images) | ✅ Complete |
| [Generate passwords](#31-password-generation) | ✅ Complete |
| [Bootstrap servers](#32-bootstrap) | ✅ Complete |
| [Run prechecks](#33-prechecks) | ✅ Complete |
| [Deploy full stack](#34-deployment) | ✅ Complete |
| [Post-deploy configuration](#35-post-deploy) | ✅ Complete |
| [Install OpenStack CLI](#41-cli-installation) | ✅ Complete |
| [Integrate OSC IMS Module with OpenStack](#41-cli-installation) | N/A |
| [Integrate OSC IMS Module with BMW FOCOM and NFO](#41-cli-installation) | N/A |
---

## 1. Infrastructure Setup

### 1.1 Controller VM Setup
- **Node**: 192.168.8.51
- **OS**: Centos 9
- **Resources**: 8GB RAM, 40GB disk
- **Status**: ✅ Complete

**Network Configuration**:
- Interface: enp1s0 (192.168.8.51/24)
- External: enp8s0 (for Neutron, no IP)

### 1.2 Compute Node Setup
- **Node**: 192.168.8.35
- **OS**: Centos 9
- **Resources**: Available for hypervisor
- **Status**: ✅ Complete

**Network Configuration**:
- Interface: ens3 (192.168.8.35/24)
- Note: Single interface configuration

### 1.3 Baremetal Node (RT-Workers)

| Node      | Purpose       | Provisioned By   | Redfish Support | CPU | Memory | NIC |
| --        | --            | --               | --  | --  | --     | --  |
| Joule     | K8S Worker-RT | Redfish API      | Yes | Saphire    |        |     |
| Lavoisier | Worker-RT     | Redfish API      | Yes | Saphire   |        |     |
| Newton    | OKD Worker-RT | OpenStack [ToDo] | Yes | Broadwell    |        |     |
| Einstein  | Worker-RT     | Manual           | No    | Haskell    |        |     |


### 1.3 Container Runtime
```bash
# Install Podman compatibility layer
sudo dnf install -y podman-docker
sudo systemctl enable --now podman.socket

# Install Python bindings (system-wide for Ansible)
sudo pip3 install podman
```

### 1.4 Access Configuration
```bash
# SSH keys
ssh-keygen -t rsa
ssh-copy-id root@192.168.8.35

# Passwordless sudo
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$USER
```

---

## 2. Kolla-Ansible Installation

### 2.1 Python Environment
```bash
python3 -m venv ~/kolla-venv
source ~/kolla-venv/bin/activate
pip install -U pip
pip install 'ansible-core>=2.14,<2.16'
pip install kolla-ansible==18.1.0
```

### 2.2 Inventory Configuration

**File**: `~/multinode`
```ini
[control]
controller ansible_host=192.168.8.51 ansible_connection=local

[network]
controller ansible_connection=local

[compute]
baremetal-01 ansible_host=192.168.8.35 ansible_user=root ansible_ssh_private_key_file=/home/infidel/.ssh/id_rsa

[monitoring]
controller ansible_connection=local

[storage]
controller ansible_connection=local

[deployment]
localhost ansible_connection=local

[baremetal:children]
control
network
compute
monitoring
storage
```
**File**: `~/host_vars/controller.yml`
```yaml
network_interface: "enp1s0"
api_interface: "enp1s0"
neutron_external_interface: "enp8s0"
```

**File**: `~/host_vars/baremetal-01.yml`
```yaml
network_interface: "ens3"
api_interface: "ens3"
tunnel_interface: "ens3"
neutron_external_interface: "ens3"
```

### 2.3 Global Configuration

**File**: `/etc/kolla/globals.yml`
```yaml
kolla_base_distro: "rocky"
kolla_internal_vip_address: "192.168.8.51"
kolla_container_engine: "podman"
network_interface: "enp1s0"
neutron_external_interface: "enp8s0"
enable_neutron_provider_networks: "yes"

# Disable unnecessary services
enable_cinder: "no"
enable_fluentd: "no"
enable_haproxy: "no"
enable_host_os_checks: false

# O2 IMS Requirements
enable_watcher: "yes"

# Ironic - Redfish virtual media only
enable_ironic: "yes"
enable_ironic_ipxe: "no"
enable_ironic_pxe_uefi: "no"
enable_ironic_inspector: "no"
enable_ironic_neutron_agent: "yes"
ironic_enabled_boot_interfaces: ['redfish-virtual-media']
ironic_enabled_deploy_interfaces: ['direct']
ironic_default_boot_interface: 'redfish-virtual-media'
ironic_default_deploy_interface: 'direct'
```

### 2.4 Ironic Images

**Download IPA (Ironic Python Agent)**:
```bash
sudo mkdir -p /etc/kolla/config/ironic
cd /etc/kolla/config/ironic

sudo wget https://tarballs.opendev.org/openstack/ironic-python-agent/dib/files/ipa-centos9-stable-2024.1.kernel \
  -O ironic-agent.kernel

sudo wget https://tarballs.opendev.org/openstack/ironic-python-agent/dib/files/ipa-centos9-stable-2024.1.initramfs \
  -O ironic-agent.initramfs
```

---

## 3. OpenStack Deployment

### 3.1 Password Generation
```bash
cd ~
source ~/kolla-venv/bin/activate
kolla-genpwd
```

### 3.2 Bootstrap
```bash
kolla-ansible -i ~/multinode bootstrap-servers
```

**Actions**:
- Install Docker/Podman dependencies
- Configure system requirements
- Prepare nodes for deployment

### 3.3 Prechecks
```bash
kolla-ansible -i ~/multinode prechecks
```

**Validates**:
- Network connectivity
- System requirements
- Configuration correctness

### 3.4 Deployment
```bash
kolla-ansible -i ~/multinode deploy
```

**Duration**: 15-30 minutes
**Actions**: Pull images, deploy containers, configure services

### 3.5 Post-Deploy
```bash
kolla-ansible -i ~/multinode post-deploy
```

**Generates**: `/etc/kolla/admin-openrc.sh` (credentials file)

---

## 4. Service Verification

### 4.1 CLI Installation
```bash
source ~/kolla-venv/bin/activate
pip install python-openstackclient python-watcherclient
source /etc/kolla/admin-openrc.sh
```

### 4.2 Core Services
```bash
# Verify all services
openstack service list

# Check compute services
openstack compute service list

# Verify hypervisor
openstack hypervisor list
```

**Expected Output**:
| Service | Type | Status |
|---------|------|--------|
| keystone | identity | ✅ |
| nova | compute | ✅ |
| neutron | network | ✅ |
| glance | image | ✅ |
| placement | placement | ✅ |
| heat | orchestration | ✅ |

### 4.3 Watcher Verification
```bash
# Verify Watcher services
openstack optimize service list

# List available strategies
openstack optimize strategy list

# Check running containers
sudo podman ps | grep watcher
```

**Expected Containers**:
- `watcher_api`
- `watcher_decision_engine`
- `watcher_applier`

### 4.4 Ironic Verification
```bash
# List bare metal drivers
openstack baremetal driver list

# Check Ironic containers
sudo podman ps | grep ironic
```

**Status**: ⚠️ Partial - API/Conductor running, dnsmasq volume issue

**Expected Containers**:
- `ironic_api` ✅
- `ironic_conductor` ✅
- `ironic_dnsmasq` ❌ (volume error)

### 4.5 VM Testing
```bash
# Download test image
wget http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img

# Upload image
openstack image create "cirros" \
  --file cirros-0.6.2-x86_64-disk.img \
  --disk-format qcow2 \
  --container-format bare \
  --public

# Create network
openstack network create --share --provider-network-type vxlan demo-net
openstack subnet create --network demo-net \
  --subnet-range 10.0.0.0/24 \
  --gateway 10.0.0.1 \
  --allocation-pool start=10.0.0.100,end=10.0.0.200 \
  demo-subnet

# Create flavor
openstack flavor create --ram 512 --disk 1 --vcpus 1 m1.tiny

# Launch VM
openstack server create --image cirros --flavor m1.tiny \
  --network demo-net test-vm

# Verify
openstack server list
```

---

## 5. StarlingX Installation


### Post Installation

![](../assets/timeline.png)

- Machine: Galileo
- ISO: StarlingX.iso

#### Post Installation

1. Boot into starlingx.iso by any means (USB Mount, PXE, or Virtual-Media)
2. Choose AIO cli installation (automatic)

### Controller Bootstrap

Populate cluster setup

```yaml
system_mode: simplex
dns_servers:
  - 8.8.8.8
  - 8.8.4.4
external_oam_subnet: 192.168.8.0/24
external_oam_gateway_address: 192.168.8.9
external_oam_floating_address: 192.168.8.35
external_oam_node_0_address: 192.168.8.11
admin_username: admin
admin_password: Bmwlabece@123
ansible_become_pass: Bmwlabece@123
```
### Controller Setup

#### OAM Interface Configuration

```bash
[sysadmin@localhost ~(keystone_admin)]$ system host-if-modify controller-0 enp5s0f0 -c platform
+------------------+--------------------------------------+
| Property         | Value                                |
+------------------+--------------------------------------+
| ifname           | enp5s0f0                             |
| iftype           | ethernet                             |
| ports            | ['enp5s0f0']                         |
| imac             | 18:31:bf:7d:ce:8e                    |
| imtu             | 1500                                 |
| ifclass          | platform                             |
| ptp_role         | none                                 |
| aemode           | None                                 |
| schedpolicy      | None                                 |
| txhashpolicy     | None                                 |
| primary_reselect | None                                 |
| uuid             | 8b5c760a-20a6-4551-aba2-969208cd7723 |
| ihost_uuid       | 25b378b0-99de-4a0e-b493-8fc0b419c9a2 |
| vlan_id          | None                                 |
| uses             | []                                   |
| used_by          | []                                   |
| created_at       | 2025-11-06T15:34:08.879847+00:00     |
| updated_at       | 2025-11-06T15:52:42.570230+00:00     |
| sriov_numvfs     | 0                                    |
| sriov_vf_driver  | None                                 |
| max_tx_rate      | None                                 |
| ipv4_mode        | None                                 |
| ipv6_mode        | None                                 |
| accelerated      | [True]                               |
+------------------+--------------------------------------+

[sysadmin@localhost ~(keystone_admin)]$ system interface-network-assign controller-0 enp5s0f0 oam
+--------------+--------------------------------------+
| Property     | Value                                |
+--------------+--------------------------------------+
| hostname     | controller-0                         |
| uuid         | c579fca3-c8b2-4aec-9610-413d1fcd84ac |
| ifname       | enp5s0f0                             |
| network_name | oam                                  |
+--------------+--------------------------------------+
```

#### NTP Setup
```bash
[sysadmin@localhost ~(keystone_admin)]$ system ntp-modify ntpservers=0.pool.ntp.org,1.pool.ntp.org
+--------------+--------------------------------------+
| Property     | Value                                |
+--------------+--------------------------------------+
| uuid         | d4504a82-37b4-462c-a1a5-1c348966d700 |
| ntpservers   | 0.pool.ntp.org,1.pool.ntp.org        |
| isystem_uuid | 26b80906-99ec-48fd-b8cc-768781aa0964 |
| created_at   | 2025-11-06T15:33:05.113521+00:00     |
| updated_at   | None                                 |
+--------------+--------------------------------------+
```

#### Host Filesystems
```bash
# Instances filesystem for VM ephemeral storage
[sysadmin@controller-0 ~(keystone_admin)]$ system host-fs-add controller-0 instances=100
+----------------+--------------------------------------+
| Property       | Value                                |
+----------------+--------------------------------------+
| uuid           | 8ecab35d-acc7-4db9-ac7b-6aecdb2b5c9d |
| name           | instances                            |
| size           | 100                                  |
| logical_volume | instances-lv                         |
| state          | Creating (on unlock)                 |
| capabilities   | {'functions': []}                    |
| created_at     | 2025-11-06T16:49:59.675244+00:00     |
| updated_at     | None                                 |
+----------------+--------------------------------------+

# Filesystem allocation summary (1394GB total disk)
[sysadmin@controller-0 ~(keystone_admin)]$ system host-fs-list controller-0
+--------------------------------------+-----------+------+--------------+----------------------+----------------------------+
| UUID                                 | FS Name   | Size | Logical      | State                | Capabilities               |
|                                      |           | in   | Volume       |                      |                            |
|                                      |           | GiB  |              |                      |                            |
+--------------------------------------+-----------+------+--------------+----------------------+----------------------------+
| 55bf0031-a10a-4022-8a57-195b156588b1 | backup    | 25   | backup-lv    | In-Use               | {'functions': []}          |
| 9dc5d124-986b-4a4c-bc2c-88d94a0790b7 | ceph      | 20   | ceph-lv      | Ready                | {'functions': ['monitor']} |
| 5a197360-3f1e-4a0f-a094-24cef6c0e841 | docker    | 60   | docker-lv    | In-Use               | {'functions': []}          |
| 8ecab35d-acc7-4db9-ac7b-6aecdb2b5c9d | instances | 100  | instances-lv | Creating (on unlock) | {'functions': []}          |
| 16d11eda-18ca-45b0-9a96-dd4e16d0fb22 | kubelet   | 10   | kubelet-lv   | In-Use               | {'functions': []}          |
| 37d022c9-7225-44de-b977-3d805914166c | log       | 8    | log-lv       | In-Use               | {'functions': []}          |
| 88c58f0b-0835-4fab-b58b-6c8846055684 | root      | 20   | root-lv      | In-Use               | {'functions': []}          |
| d1c043fd-844a-4a4c-97b5-5cf03ee09199 | scratch   | 16   | scratch-lv   | In-Use               | {'functions': []}          |
| 8d7d4e47-e011-43a9-84c5-3746835fed17 | var       | 20   | var-lv       | In-Use               | {'functions': []}          |
+--------------------------------------+-----------+------+--------------+----------------------+----------------------------+
# Total allocated: ~279GB, Remaining: ~1115GB available
```

#### Data Network Configuration
```bash
# Available network interfaces
[sysadmin@controller-0 ~(keystone_admin)]$ system host-port-list controller-0
+--------------------------------------+----------+----------+--------------+--------+-----------+-------------+------------------------------------------------+
| uuid                                 | name     | type     | pci address  | device | processor | accelerated | device type                                    |
+--------------------------------------+----------+----------+--------------+--------+-----------+-------------+------------------------------------------------+
| 1ebc0427-9a69-49e4-8cb6-72abb43e0841 | enp3s0f0 | ethernet | 0000:03:00.0 | 0      | 0         | True        | Ethernet Controller X710 for 10GbE SFP+ [1572] |
| a8dd67eb-3242-462c-b215-7a8748593f47 | enp3s0f1 | ethernet | 0000:03:00.1 | 0      | 0         | True        | Ethernet Controller X710 for 10GbE SFP+ [1572] |
| be3d3554-0154-45f6-a58d-8e01e2b9a2a6 | enp5s0f0 | ethernet | 0000:05:00.0 | 0      | 0         | True        | I350 Gigabit Network Connection [1521]         |
| 7befa9f6-0e48-4764-b442-1ffbfb030137 | enp5s0f1 | ethernet | 0000:05:00.1 | 0      | 0         | True        | I350 Gigabit Network Connection [1521]         |
| 50f10d0b-bad5-475b-a6ea-efea3453c2ad | ens1f0   | ethernet | 0000:02:00.0 | 0      | 0         | True        | 82580 Gigabit Network Connection [1516]        |
| f1b98994-538d-4d33-8025-f0fb05eedaf8 | ens1f1   | ethernet | 0000:02:00.1 | 0      | 0         | True        | 82580 Gigabit Network Connection [1516]        |
+--------------------------------------+----------+----------+--------------+--------+-----------+-------------+------------------------------------------------+

# Configure data interface (enp5s0f0 reused for data after platform setup)
[sysadmin@controller-0 ~(keystone_admin)]$ system host-if-modify -m 1500 -n data0 -c data controller-0 8b5c760a-20a6-4551-aba2-969208cd7723
+------------------+--------------------------------------+
| Property         | Value                                |
+------------------+--------------------------------------+
| ifname           | data0                                |
| iftype           | ethernet                             |
| ports            | ['enp5s0f0']                         |
| imac             | 18:31:bf:7d:ce:8e                    |
| imtu             | 1500                                 |
| ifclass          | data                                 |
| ptp_role         | none                                 |
| aemode           | None                                 |
| schedpolicy      | None                                 |
| txhashpolicy     | None                                 |
| primary_reselect | None                                 |
| uuid             | 8b5c760a-20a6-4551-aba2-969208cd7723 |
| ihost_uuid       | 25b378b0-99de-4a0e-b493-8fc0b419c9a2 |
| vlan_id          | None                                 |
| uses             | []                                   |
| used_by          | []                                   |
| created_at       | 2025-11-06T15:34:08.879847+00:00     |
| updated_at       | 2025-11-06T16:52:07.366991+00:00     |
| sriov_numvfs     | 0                                    |
| sriov_vf_driver  | None                                 |
| max_tx_rate      | None                                 |
| ipv4_mode        | static                               |
| ipv6_mode        | disabled                             |
| accelerated      | [True]                               |
+------------------+--------------------------------------+

# Create datanetwork
[sysadmin@controller-0 ~(keystone_admin)]$ system datanetwork-add datanet0 vlan
+--------------+--------------------------------------+
| Property     | Value                                |
+--------------+--------------------------------------+
| id           | 1                                    |
| uuid         | 62599454-da9f-4021-b059-52ad713e9d7a |
| name         | datanet0                             |
| network_type | vlan                                 |
| mtu          | 1500                                 |
| description  | None                                 |
+--------------+--------------------------------------+

# Assign datanetwork to interface
[sysadmin@controller-0 ~(keystone_admin)]$ system interface-datanetwork-assign controller-0 8b5c760a-20a6-4551-aba2-969208cd7723 datanet0
+------------------+--------------------------------------+
| Property         | Value                                |
+------------------+--------------------------------------+
| hostname         | controller-0                         |
| uuid             | 2cb3e0bf-d3c4-4f93-947a-f1d1f9a132ae |
| ifname           | data0                                |
| datanetwork_name | datanet0                             |
+------------------+--------------------------------------+
```

#### CPU Configuration for OpenStack
```bash
# Assign platform cores (6 cores on processor 0)
[sysadmin@controller-0 ~(keystone_admin)]$ system host-cpu-modify -f platform -p0 6 controller-0
# Output: Cores 0-5 (and their HT siblings) assigned to Platform

# Assign vSwitch cores (2 cores required for OVS-DPDK)
[sysadmin@controller-0 ~(keystone_admin)]$ system host-cpu-modify -f vswitch -p0 2 controller-0
# Output: Cores 6-7 (and their HT siblings) assigned to vSwitch
# Remaining cores (8-13 on both processors) assigned to Application (VMs)
```

#### Storage Backend
```bash
# Rook-Ceph already configured
[sysadmin@controller-0 ~(keystone_admin)]$ system storage-backend-list
+--------------------------------------+-----------------+-----------+----------------------+----------+----------------+---------------------------------------------+
| uuid                                 | name            | backend   | state                | task     | services       | capabilities                                |
+--------------------------------------+-----------------+-----------+----------------------+----------+----------------+---------------------------------------------+
| 76763271-d927-4b39-ad82-dd41bfb9a2e6 | ceph-rook-store | ceph-rook | configuring-with-app | uploaded | block,         | deployment_model: controller replication: 1 |
|                                      |                 |           |                      |          | filesystem     | min_replication: 1                          |
|                                      |                 |           |                      |          |                |                                             |
+--------------------------------------+-----------------+-----------+----------------------+----------+----------------+---------------------------------------------+
```

#### Applications Status
```bash
[sysadmin@controller-0 ~(keystone_admin)]$ system application-list
+--------------------------+-----------+-------------------------------------------+------------------+----------+-----------+
| application              | version   | manifest name                             | manifest file    | status   | progress  |
+--------------------------+-----------+-------------------------------------------+------------------+----------+-----------+
| cert-manager             | 24.09-79  | cert-manager-fluxcd-manifests             | fluxcd-manifests | applied  | completed |
| dell-storage             | 24.09-26  | dell-storage-fluxcd-manifests             | fluxcd-manifests | uploaded | completed |
| nginx-ingress-controller | 24.09-66  | nginx-ingress-controller-fluxcd-manifests | fluxcd-manifests | applied  | completed |
| oidc-auth-apps           | 24.09-63  | oidc-auth-apps-fluxcd-manifests           | fluxcd-manifests | uploaded | completed |
| platform-integ-apps      | 24.09-144 | platform-integ-apps-fluxcd-manifests      | fluxcd-manifests | uploaded | completed |
| rook-ceph                | 24.09-71  | rook-ceph-fluxcd-manifests                | fluxcd-manifests | uploaded | completed |
+--------------------------+-----------+-------------------------------------------+------------------+----------+-----------+
```

#### System Information
```bash
[sysadmin@controller-0 ~(keystone_admin)]$ cat /etc/build.info
SW_VERSION="24.09"
BUILD_TARGET="Host Installer"
BUILD_TYPE="Formal"
BUILD_ID="20250124T210100Z"
SRC_BUILD_ID="12"

JOB="STX_10.0_build_debian"
BUILD_BY="jenkins"
BUILD_NUMBER="13"
BUILD_HOST="yow2-wrcp2-lx"
BUILD_DATE="2025-01-24 21:01:00 +0000"
```

#### Disk Layout
```bash
[sysadmin@controller-0 ~(keystone_admin)]$ system host-disk-list controller-0
+--------------------------------------+-------------+------------+-------------+----------+---------------+--------------+----------------------------------+-------------------------------------------------+
| uuid                                 | device_node | device_num | device_type | size_gib | available_gib | rpm          | serial_id                        | device_path                                     |
+--------------------------------------+-------------+------------+-------------+----------+---------------+--------------+----------------------------------+-------------------------------------------------+
| 70e317fb-502b-4b6d-9ae4-9eecd6a8ba87 | /dev/sda    | 2048       | HDD         | 1394.375 | 0.0           | Undetermined | 0008077b0dbf92c622588d0030f81201 | /dev/disk/by-path/pci-0000:81:00.0-scsi-0:2:0:0 |
+--------------------------------------+-------------+------------+-------------+----------+---------------+--------------+----------------------------------+-------------------------------------------------+
```

### Next Steps

1. **Unlock controller-0** to apply all configurations
2. **Apply Rook-Ceph application** to complete storage setup
3. **Add Ceph OSDs** from remaining ~1115GB disk space
4. **Download and install stx-openstack** for VM support
```bash
   wget https://mirror.starlingx.windriver.com/mirror/starlingx/release/10.0.0/debian/openstack/outputs/helm-charts/stx-openstack-24.09-0-debian-stable-latest.tgz
   system application-upload stx-openstack-24.09-0-debian-stable-latest.tgz
   system application-apply stx-openstack
```

---

## 6. O2 IMS Integration

### 6.1 O2 Adapter Installation
**Status**: On Going

**Requirements**:
- O2 IMS service implementation
- O-RAN O2 interface compliance
- Integration with Watcher and Ironic

1. Git Clone project
1. Fetch admin_openrc.sh from openstack

#### 6.1.1 Setup Keycloak Dev mode

1. Crete Local Keycloak Instance
    ```bash
    podman run --name keycloak -p 8080:8080 -e KEYCLOAK_ADMIN=admin -e KEYCLOAK_ADMIN_PASSWORD=admin -e KC_HOSTNAME=localhost quay.io/keycloak/keycloak:latest start-dev
    ```
1. Update admin password of keycloak instance
    ```bash
    # From Host
    podman exec -it keycloak /bin/bash
    # From Container
    bash-5.1$ cd /opt/keycloak/bin
    bash-5.1$ ./kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin
    bash-5.1$ ./kcadm.sh update realms/master -s sslRequired=NONE
    ```
1.  Create Keycloak client open keycloak dashboard from `http://localhost:8080`
    1. Goto Clients -> Create Client
    1. asdasldk
    1. asdkjasd

1. Establish communication between O2-IMS and INF (OpenStack)
### 6.2 O2 API Configuration
**Status**: ❌ Not Started

**Configuration Points**:
- O2 IMS endpoint URL
- Authentication credentials
- API version compatibility
- Resource model mapping

### 6.3 Infrastructure Inventory
**Status**: ❌ Not Started

**Tests Required**:
- Query available resources
- Resource pool information
- Deployment capability discovery

### 6.4 Resource Lifecycle
**Status**: ❌ Not Started

**Validation Tests**:
- Bare metal provisioning request
- Resource allocation tracking
- Deprovisioning workflow
- State change notifications

### 6.5 Notification Service
**Status**: ❌ Not Started

**Event Types**:
- Resource state changes
- Alarms and faults
- Capacity warnings
- Lifecycle events

---

## Access Information

### Horizon Dashboard
- **URL**: http://192.168.8.51
- **Username**: admin
- **Password**: `grep keystone_admin_password /etc/kolla/passwords.yml`

### CLI Access
```bash
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
```

---

## Technical Issues Log

| Issue | Root Cause | Solution | Status | Section |
|-------|------------|----------|--------|---------|
| RHEL not recognized | OS check too strict | `enable_host_os_checks: false` | ✅ Fixed | [2.3](#23-global-configuration) |
| Interface mismatch | Different NIC names | Use host_vars per node | ✅ Fixed | [2.2](#22-inventory-configuration) |
| Podman module missing | Ansible needs bindings | `sudo pip3 install podman` | ✅ Fixed | [1.3](#13-container-runtime) |
| Fluentd mount error | Missing `/var/log/journal` | Disable fluentd | ✅ Fixed | [2.3](#23-global-configuration) |
| Cinder no backend | No storage configured | `enable_cinder: no` | ✅ Fixed | [2.3](#23-global-configuration) |
| Single interface | Only one NIC | Share interface for all traffic | ✅ Fixed | [1.2](#12-compute-node-setup) |
| Ironic dnsmasq error | Volume format issue | Disable inspector/PXE | ⚠️ Workaround | [4.4](#44-ironic-verification) |

---

## Network Topology

### Physical Network
- **Subnet**: 192.168.8.0/24
- **Controller**: 192.168.8.51 (enp1s0)
- **Compute**: 192.168.8.35 (ens3)

### Tenant Networks
- **Type**: VXLAN overlays
- **Example Range**: 10.0.0.0/24
- **DHCP**: Neutron-managed (tenant networks only)

### Traffic Flow
```
Management: Controller ←→ Compute (192.168.8.x)
VM Traffic: Tenant VMs ←→ VXLAN tunnel ←→ External
```

---

## Key Commands Reference

### Deployment Operations
```bash
cd ~
source ~/kolla-venv/bin/activate

# Deploy/Redeploy
kolla-ansible -i ~/multinode deploy

# Reconfigure services
kolla-ansible -i ~/multinode reconfigure

# Deploy specific service
kolla-ansible -i ~/multinode deploy --tags watcher
```

### Container Management
```bash
# List containers
sudo podman ps

# Check specific service
sudo podman ps | grep <service>

# View logs
sudo podman logs <container_name>

# Restart container
sudo podman restart <container_name>
```

### OpenStack Operations
```bash
# Load credentials
source /etc/kolla/admin-openrc.sh

# Service status
openstack service list
openstack compute service list
openstack hypervisor list

# Watcher operations
openstack optimize service list
openstack optimize audit create --strategy basic --name test

# Ironic operations
openstack baremetal driver list
openstack baremetal node list
```

---

## Documentation & References

- **Kolla-Ansible**: https://docs.openstack.org/kolla-ansible/latest/
- **O-RAN O2 Specification**: https://orandownloadsweb.azurewebsites.net/specifications
- **Ironic Redfish Driver**: https://docs.openstack.org/ironic/latest/admin/drivers/redfish.html
- **Watcher Documentation**: https://docs.openstack.org/watcher/latest/
- **OpenStack CLI**: https://docs.openstack.org/python-openstackclient/latest/

---

**Environment**: Lab/Test
**OS**: RHEL 9
**Container Engine**: Podman
**Deployment Tool**: Kolla-Ansible 18.1.0
**Last Updated**: 2025-11-03
**Primary Operator**: infidel
**Current State**: OpenStack operational, O2 IMS integration pending
