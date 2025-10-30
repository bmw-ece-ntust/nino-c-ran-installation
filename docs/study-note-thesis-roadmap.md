# Study Notes: Thesis Roadmap


<!-- vim-markdown-toc GFM -->

* [1. Bimo CICD Discussion](#1-bimo-cicd-discussion)
* [2. O-RU Integration Status](#2-o-ru-integration-status)
* [Summary Status](#summary-status)
* [Worker Node Specifications](#worker-node-specifications)
* [Detailed Status](#detailed-status)
    * [OAI gNB - LiteON C3 (worker-rt-00)](#oai-gnb---liteon-c3-worker-rt-00)
    * [OAI gNB - LiteON C3 (worker-rt-01)](#oai-gnb---liteon-c3-worker-rt-01)
    * [OAI gNB - Pegatron C3 (lavoisier)](#oai-gnb---pegatron-c3-lavoisier)
    * [srsRAN - LiteON C3](#srsran---liteon-c3)
* [Key Technical Findings](#key-technical-findings)
    * [SR-IOV VLAN Issue (XXV710 NIC)](#sr-iov-vlan-issue-xxv710-nic)
    * [CPU Instruction Set Compatibility (E810 NIC)](#cpu-instruction-set-compatibility-e810-nic)
* [Action Items](#action-items)
    * [Immediate (This Week)](#immediate-this-week)
    * [Short Term (Next Week)](#short-term-next-week)
    * [Pending External](#pending-external)
* [3. Experimental Plan:](#3-experimental-plan)
    * [Current Infrastructure](#current-infrastructure)
    * [Experimental Setup Summary](#experimental-setup-summary)

<!-- vim-markdown-toc -->


## 1. Bimo CICD Discussion

**GitHub Actions vs Traditional Infrastructure**
- GitHub Actions removes the need for dedicated infrastructure. Jenkins requires servers; GitHub Actions does not. The free tier has limits on concurrent jobs and build minutes.
- The automation work remains unchanged. Bimo confirmed developers still write the pipeline scripts. The complexity of CI/CD automation has not been eliminated—only the infrastructure burden.
- No existing pipeline scripts for GNB, rApp, or O2-related builds. These must be written from scratch.

**On-Premise Integration Limitations**
- GitHub Actions cannot reach on-premise facilities for integration testing. After build completion, the CI script needs access to local APIs—SMO, O-RU Mplane, or other devices—to validate software on the end-to-end environment.
- The CICD focus is integration, not just compilation. Build process completes, but validation requires local device access. GitHub Actions runs on cloud infrastructure with no direct path to private networks.
- For integration testing with physical O-RU units or local SMO instances, on-premise Jenkins remains necessary. GitHub Actions handles public repository builds; Jenkins handles everything that touches local hardware or private APIs.
- Split approach possible: GitHub Actions for build and unit tests, Jenkins for integration tests requiring local facility access. This introduces pipeline complexity and state management between two systems.


---
## 2. O-RU Integration Status

## Summary Status
| Software   | Vendor   | Connection | Status      | Worker Node | Deadline   |
| ---------- | -------- | ---------- | ----------- | ----------- | ---------- |
| OAI gNB    | LiteON   | C3         | Done        | worker-rt-00| Oct 24     |
| OAI gNB    | LiteON   | C3         | Blocked     | worker-rt-01| Oct 31     |
| OAI gNB    | Pegatron | C3         | Blocked     | lavoisier   | Oct 31     |
| OAI gNB    | Foxconn  | C3         | Not Started | TBD         | TBD        |
| srsRAN     | LiteON   | C3         | Blocked     | TBD         | Oct 30     |

## Worker Node Specifications
| Worker       | CPU Generation   | Model | AVX512 | Memory | NIC              | RHEL  | Hardware      |
| ------------ | ---------------- | ----- | ------ | ------ | ---------------- | ----- | ------------- |
| worker-rt-00 | Sapphire Rapids  | 106   | Yes    | 128GB  | Intel E810-XXV   | 9.6   | Dell R750     |
| worker-rt-01 | Broadwell-EP     | 79    | **No** | 64GB   | Intel E810-XXV   | 9.5   | Supermicro    |
| lavoisier    | Sapphire Rapids  | 143   | Yes    | 256GB  | Intel XXV710     | 9.2   | Supermicro    |

---

## Detailed Status

### OAI gNB - LiteON C3 (worker-rt-00)
**Status**: SUCCESS - Operational
**Deadline**: Oct 24 (Met)

**Components**
- Control Plane: OK
- User Plane: OK

**Setup**
- OS: Automated installation
- Deployment: Helm/K8s by user YMA
- SR-IOV Device Plugin: Enabled

**Issues Resolved**
| Issue | Root Cause | Solution |
|-------|------------|----------|
| Boot loop | Missing `iommu=pt` | Added to GRUB config |
| VF creation failure | SR-IOV operator validation | Kernel parameter fix |
| MTU mismatch | 9600 vs 9216 | Aligned to 9216 |
| PTP sync failure | Missing UDS socket | Added `uds_address` to ptp4l.conf |
| CPU isolation errors | Kubelet config mismatch | Fixed `reservedSystemCPUs` |
| SSH hang | CPU allocation deadlock | Aligned kubelet with kernel isolation |
| Pod scheduling failure | Insufficient allocatable CPU | Reduced from 20 to 16 cores |

---

### OAI gNB - LiteON C3 (worker-rt-01)
**Status**: BLOCKED - Container crashes on Broadwell CPU
**Deadline**: Oct 31

**Components**
- Control Plane: Not tested
- User Plane: Not tested

**Setup**
- OS: RHEL 9.5 RT configured
- SR-IOV: VFs created, bound to vfio-pci (VLAN 6)
- Deployment: Helm/K8s

**Current Blocker**
| Issue | Root Cause | Solution Status |
|-------|------------|-----------------|
| Immediate crash after DPDK probe | DPDK/xran libraries compiled with AVX512 instructions | In progress - rebuilding container |

**Root Cause Analysis**
- Container built on Sapphire Rapids node with native optimizations
- DPDK 20.11.9 compiled without CPU constraints (uses `-march=native`)
- xran FHI library compiled without CFLAGS
- Broadwell CPU (model 79) lacks AVX512 instruction set
- Binary crashes on illegal instruction when DPDK PMD initializes

**Solution in Progress**
Rebuilding container with CPU constraints:
```dockerfile
ENV CFLAGS="-march=broadwell -mtune=broadwell"
ENV CXXFLAGS="-march=broadwell -mtune=broadwell"

# DPDK build with constraints
RUN meson setup build && ninja -C build

# xran build with constraints
RUN CFLAGS="-march=broadwell" make XRAN_LIB_SO=1
```

**ETA**: Container rebuild in progress

---

### OAI gNB - Pegatron C3 (lavoisier)
**Status**: BLOCKED - Intermittent VIRTCHNL failures with port VLAN
**Deadline**: Oct 31

**Components**
- Control Plane: OK
- User Plane: Intermittent

**Setup**
- OS: RHEL 9.2 RT by user Ming
- SR-IOV: Manual VF management (device plugin disabled)
- NIC: Intel XXV710 25GbE (PCI 70:00.0)
- Deployment: Helm/K8s with hostNetwork

**Current Blocker**
| Issue | Root Cause | Current Status |
|-------|------------|----------------|
| Intermittent DPDK initialization failure | iavf kernel driver auto-binds before vfio-pci, leaves stale VIRTCHNL mailbox state | Investigating workaround |

**Technical Analysis**
Problem sequence:
1. VF created → iavf auto-binds (via udev)
2. Port VLAN configured while iavf bound
3. iavf removed → vfio-pci binds
4. Container starts (time gap)
5. DPDK initializes → VF mailbox in stale state → 50% success rate

**Tested Configurations**
| VLAN | Container Mode | Result | Notes |
|------|----------------|--------|-------|
| 0    | Any            | 100% success | No port VLAN = no capability conflict |
| 3    | Baremetal      | 100% success | Direct vfio-pci binding, immediate start |
| 3    | hostNetwork    | ~50% success | Timing-dependent mailbox state |
| 103  | hostNetwork    | ~50% success | Same timing issue |

**Workarounds Under Evaluation**
1. Use VLAN 0 + configure VLAN at switch level (requires network team)
2. Blacklist iavf permanently, setup VFs at boot via systemd
3. Use baremetal deployment (no containerization)

**Decision Pending**: Switch configuration access or deployment model change

---

### srsRAN - LiteON C3
**Status**: BLOCKED - Awaiting vendor support
**Deadline**: Oct 30

**Components**
- Control Plane: Not started
- User Plane: Not started

**Blocking Issues**
- Multus CNI integration required for SR-IOV
- Git issue opened: Oct 21
- Email sent to srsRAN team: Oct 21
- No response received

**Actions Required**
- Escalate to srsRAN support
- Consider alternative: OAI CU-CP + srsRAN CU-UP split architecture

---

## Key Technical Findings

### SR-IOV VLAN Issue (XXV710 NIC)
**Problem**: Port VLAN configuration on VFs causes VIRTCHNL capability mismatch in containers

**Root Cause**:
- Linux kernel auto-loads iavf driver when VFs created (udev)
- PF configures port VLAN while iavf bound to VF
- Driver switch (iavf → vfio-pci) leaves residual mailbox state
- Container start has time gap → DPDK catches unpredictable VF state

**Impact**: 50% success rate with non-zero VLANs in containers

**Kernel Evidence** (from dmesg):
```
iavf 0000:70:02.0: MAC address assigned
iavf 0000:70:02.0: renamed from eth0
i40e 0000:70:00.0: Setting VLAN 3, QOS 0x0 on VF 0
iavf 0000:70:02.0: Removing device
vfio-pci 0000:70:02.0: enabling device (retry 3x)
```

**Solution Options**:
1. VLAN 0 only (requires switch-side VLAN config)
2. Baremetal deployment model
3. Systemd-managed VF setup before kubelet starts

---

### CPU Instruction Set Compatibility (E810 NIC)
**Problem**: Container crashes immediately on Broadwell CPU

**Root Cause**:
- Container built on Sapphire Rapids with `-march=native`
- DPDK 20.11.9 library contains AVX512 instructions
- xran FHI library contains AVX512 instructions
- Broadwell CPU (family 6, model 79) lacks AVX512

**Impact**: Complete failure on worker-rt-01

**Solution**: Rebuild all components with:
```
CFLAGS="-march=broadwell -mtune=broadwell"
```

Applied to:
- DPDK meson build
- xran library make
- OAI gNB cmake build

**Status**: Container rebuild in progress

---

## Action Items

### Immediate (This Week)
- [ ] Complete container rebuild with Broadwell CPU constraints (worker-rt-01)
- [ ] Test rebuilt container on worker-rt-01
- [ ] Decide on lavoisier deployment model (VLAN 0 vs baremetal vs switch config)

### Short Term (Next Week)
- [ ] Deploy Pegatron solution on lavoisier once blocker resolved
- [ ] Document final SR-IOV VLAN configuration procedure
- [ ] Create cross-platform container build CI/CD (Broadwell + Sapphire Rapids)

### Pending External
- [ ] Network team: Switch VLAN configuration capability
- [ ] srsRAN: Multus CNI integration support
- [ ] Foxconn: Physical connection and deployment schedule

---

## 3. Experimental Plan:

### Current Infrastructure

| Component | Technology | Function | Status |
|-----------|-----------|----------|--------|
| Build System | Jenkins | CNF GNB compilation and packaging | Operational |
| Deployment System | FOCOM & NFO Module | Query Resources and Deploy built packages via DMS API (k8s API) | Operational |
| Target Platform | OSC O-Cloud | CNF runtime environment | Operational |

### Experimental Setup Summary

**Experiment 1: Baseline Deployment**
- Jenkins: Build CNF GNB package
- NFO: Replace direct DMS API (k8s API) calls with O2 interface calls for deployment
- O2 Interface: Handle resource provisioning requests
- Outcome: Establish deployment time baseline and validate O2 interface functionality

**Experiment 2: Multi-Component Integration**
- Jenkins: Orchestrate builds for DU, CU, and O-RU configuration
- NFO: Manage deployment dependencies between components using O2 interface
- O2 Interface: Configure inter-component networking and resource allocation
- Outcome: Measure dependency handling and configuration drift detection

**Experiment 3: Failure Recovery**
- Jenkins: Implement health monitoring and automated retry logic in pipeline
- NFO: Detect failures and trigger recovery procedures via O2 interface
- O2 Interface: Execute state reconciliation and rollback operations
- Outcome: Quantify detection time and recovery success rate under fault conditions

