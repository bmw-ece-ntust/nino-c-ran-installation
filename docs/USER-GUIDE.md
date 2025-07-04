# O-RAN O-DU High User Guide

> [!NOTE]
> This User Guide is based on the [O-RAN O-DU High project](https://github.com/o-ran-sc/o-du-l2/tree/master) and provides step-by-step instructions for deployment and testing.

## Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Basic Execution](#basic-execution)
- [Intel L1 Integration](#intel-l1-integration)
- [O1 Interface Configuration](#o1-interface-configuration)
- [Health Check Procedures](#health-check-procedures)
- [Containerization Deployment](#containerization-deployment)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements

- **Operating System**: Ubuntu 18.04 or higher
- **Memory**: Minimum 8GB RAM
- **CPU**: Multi-core processor (recommended 4+ cores)
- **Network**: Multiple network interfaces for O-RAN components

### Software Dependencies

- GCC 7.5 or higher
- CMAKE 3.10 or higher
- Docker (for containerization mode)
- Kubernetes/Minikube (for container orchestration)
- Netopeer2 (for O1 interface)

## Quick Start

### Network Configuration

First, assign virtual IP addresses for the O-RAN components:

```bash
# Configure ODU interface
sudo ifconfig <interface_name>:ODU "192.168.130.81"

# Configure CU Stub interface  
sudo ifconfig <interface_name>:CU_STUB "192.168.130.82"

# Configure RIC Stub interface
sudo ifconfig <interface_name>:RIC_STUB "192.168.130.80"
```

> [!IMPORTANT]
> If O1 interface is enabled, ensure IP addresses match the configuration in step [O1 Interface Configuration](#o1-interface-configuration).

## Basic Execution

Execute the components in the following order:

### 1. Start CU Stub

```bash
# Navigate to CU execution folder
cd l2/bin/cu_stub

# Run CU Stub binary
./cu_stub
```

**Expected Output:**
```
CU STUB : Received F1 Setup Request
CU STUB : Sending F1 Setup Response
```

### 2. Start RIC Stub

```bash
# Navigate to RIC execution folder
cd l2/bin/ric_stub

# Run RIC Stub binary
./ric_stub
```

**Expected Output:**
```
RIC STUB : Started RIC Stub
RIC STUB : Waiting for SCTP connection
```

### 3. Start O-DU High

```bash
# Navigate to DU execution folder
cd l2/bin/odu

# Run ODU binary
./odu
```

**Expected Output:**
```
ODU APP : Starting ODU APP
ODU APP : Cell is UP
```

> [!WARNING]
> **Execution Order**: CU Stub and RIC Stub must be started before ODU. If O1 is enabled without SMO, follow the [O1 Interface Configuration](#o1-interface-configuration) section.

## Intel L1 Integration

### Compilation with Intel L1

#### 1. Prepare Intel Libraries

```bash
# Create WLS library folder
mkdir -p l2/src/wls_lib
cp <intel_directory>/phy/wls_lib/wls_lib.h l2/src/wls_lib/

# Create DPDK library folder
mkdir -p l2/src/dpdk_lib
```

Copy the following DPDK headers to `l2/src/dpdk_lib/`:
- `rte_branch_prediction.h`
- `rte_common.h`
- `rte_config.h`
- `rte_dev.h`
- `rte_log.h`
- `rte_pci_dev_feature_defs.h`
- `rte_bus.h`
- `rte_compat.h`
- `rte_debug.h`
- `rte_eal.h`
- `rte_os.h`
- `rte_per_lcore.h`

#### 2. Build ODU with Intel L1 Support

```bash
# Navigate to build folder
cd l2/build/odu

# Build ODU Binary with Intel L1 parameters
make odu PHY=INTEL_L1 PHY_MODE=TIMER MACHINE=BIT64 MODE=FDD
```

### Intel L1 Execution

#### 1. Start Intel L1

```bash
# Setup Intel environment
cd <intel_directory>/phy/
source ./setupenv.sh

# Run L1 binary
cd <intel_directory>/FlexRAN/l1/bin/nr5g/gnb/l1

# Timer mode
./l1.sh -e

# OR Radio mode  
./l1.sh -xran
```

**L1 Ready Indication:**
```
Non BBU threads in application
===========================================================================================================
nr5g_gnb_phy2mac_api_proc_stats_thread: [PID: 8659] binding on [CPU 0] [PRIO: 0] [POLICY: 1]
wls_rx_handler (non-rt):                [PID: 8663] binding on [CPU 0]
===========================================================================================================

PHY>welcome to application console
```

#### 2. Start FAPI Translator

```bash
# Setup environment
cd <intel_directory>/phy/
source ./setupenv.sh

# Run FAPI translator
cd <intel_directory>/phy/fapi_5g/bin/
./oran_5g_fapi --cfg=oran_5g_fapi.cfg
```

#### 3. Execute O-DU with Intel L1

```bash
# Navigate to ODU folder
cd l2/bin/odu

# Export WLS library path
export LD_LIBRARY_PATH=<intel_directory>/phy/wls_lib/lib:$LD_LIBRARY_PATH

# Run ODU binary
./odu
```

## O1 Interface Configuration

When O-DU High runs with O1 enabled, it waits for initial configuration from SMO. If SMO is unavailable, configure manually using netopeer-cli:

### Push Cell Configuration

```bash
# Navigate to configuration folder
cd l2/build/config

# Start netopeer CLI
netopeer2-cli

# Connect with credentials
> connect --login netconf
Interactive SSH Authentication
Type your password:
Password: netconf!

# Push cell configuration
> edit-config --target candidate --config=cellConfig.xml
> OK
> commit
> OK

# Push RRM policy
> edit-config --target candidate --config=rrmPolicy.xml  
> OK
> commit
> OK
```

### Subsequent Configuration Updates

For additional runs, edit configuration files and increment the ID tags:

```xml
<!-- Update ID in cellConfig.xml and rrmPolicy.xml -->
<id>rrm-2</id>
```

## Health Check Procedures

### Get Alarm List via O1

Check system health using netopeer-cli:

```bash
# Start netopeer CLI
netopeer2-cli

# Connect to O-DU
> connect --login netconf
Interactive SSH Authentication
Type your password:
Password: netconf!

# Get active alarms
> get --filter-xpath /o-ran-sc-odu-alarm-v1:odu/alarms
```

**Sample Output:**
```xml
DATA
<odu xmlns="urn:o-ran:odu:alarm:1.0">
  <alarms>
    <alarm>
      <alarm-id>1009</alarm-id>
      <alarm-text>cell id [1] is up</alarm-text>
      <severity>2</severity>
      <status>Active</status>
      <additional-info>cell UP</additional-info>
    </alarm>
  </alarms>
</odu>
```

## Containerization Deployment

### Prerequisites for Container Mode

1. **Install Docker**
   ```bash
   sudo apt update
   sudo apt install docker.io
   sudo systemctl start docker
   sudo systemctl enable docker
   ```

2. **Setup Kubernetes with Minikube**
   ```bash
   # Install minikube
   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
   sudo install minikube-linux-amd64 /usr/local/bin/minikube
   
   # Start minikube with Docker driver
   minikube start --driver=docker
   ```

### Container Deployment Steps

#### 1. Clone and Compile

```bash
# Create working directory
mkdir ODU_CONTAINER
cd ODU_CONTAINER

# Clone repository
git clone "https://gerrit.o-ran-sc.org/r/o-du/l2"
cd l2

# Set Docker environment for Minikube
eval $(minikube docker-env)
```

#### 2. Build Docker Images

```bash
# Build CU container
docker build -f Dockerfile.cu -t new-cu-container:v1 .

# Build RIC container  
docker build -f Dockerfile.ric -t new-ric-container:v1 .

# Build DU container
docker build -f Dockerfile.du -t new-du-container:v1 .

# Verify images
docker images
```

#### 3. Deploy with Helm

```bash
# Deploy CU chart
cd container/cu_helm
helm install ocu cu

# Deploy DU chart
cd ../du_helm  
helm install odu du

# Deploy RIC chart
cd ../ric_helm
helm install ric ric

# Check deployment status
kubectl get all
```

#### 4. Execute in Container Mode

Open **three separate terminals** and execute:

**Terminal 1 - CU Pod:**
```bash
kubectl exec -it <CU_POD_NAME> -- bash
./cu-docker-entrypoint.sh
cd /root/l2/build/odu/bin
./cu_stub/cu_stub
```

**Terminal 2 - RIC Pod:**
```bash
kubectl exec -it <RIC_POD_NAME> -- bash  
./ric-docker-entrypoint.sh
cd /root/l2/build/odu/bin
./ric_stub/ric_stub
```

**Terminal 3 - DU Pod:**
```bash
kubectl exec -it <DU_POD_NAME> -- bash
./docker-entrypoint.sh
cd /root/l2/bin
./odu/odu
```

## Troubleshooting

### Common Issues

#### 1. Netconf Server Issues

If Netconf server breaks down:

```bash
# Navigate to scripts folder
cd l2/build/scripts

# Cleanup netconf issues
sudo ./troubleshoot_netconf.sh cleanup

# Re-execute configuration steps
# Follow sections C.3 and C.4 from installation guide
```

#### 2. Network Connectivity Issues

```bash
# Check interface status
ip addr show

# Test connectivity between components
ping 192.168.130.81  # ODU
ping 192.168.130.82  # CU Stub  
ping 192.168.130.80  # RIC Stub
```

#### 3. Port Conflicts

```bash
# Check for port usage
netstat -tlnp | grep -E "(36421|36422|8080)"

# Kill conflicting processes if needed
sudo kill -9 <PID>
```

### Log Analysis

#### ODU Logs
```bash
# Check ODU logs
tail -f /tmp/oduLog.log

# Check for specific errors
grep -i "error\|fail" /tmp/oduLog.log
```

#### Container Logs
```bash
# Check pod logs
kubectl logs <POD_NAME>

# Follow logs in real-time
kubectl logs -f <POD_NAME>
```

### Support Resources

- **O-RAN Documentation**: [O-RAN SC Documentation](https://docs.o-ran-sc.org/)
- **GitHub Issues**: [O-DU L2 Issues](https://github.com/o-ran-sc/o-du-l2/issues)
- **Community Support**: O-RAN SC Slack workspace

---

> [!TIP]
> For additional help and community support, visit the [O-RAN Software Community](https://www.o-ran.org/) website.
