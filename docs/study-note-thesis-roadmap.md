# Study Notes: Thesis Roadmap


<!-- vim-markdown-toc GFM -->

* [1. Bimo CICD Discussion](#1-bimo-cicd-discussion)
* [2. O-RU Integration Status](#2-o-ru-integration-status)
* [Summary Status](#summary-status)
    * [OAI gNB - LiteON (C3)](#oai-gnb---liteon-c3)
    * [OAI gNB - Pegatron (C3)](#oai-gnb---pegatron-c3)
    * [srsRAN - LiteON (C3)](#srsran---liteon-c3)
    * [OAI gNB - LiteON (C1)](#oai-gnb---liteon-c1)
    * [OAI gNB - Pegatron (C1)](#oai-gnb---pegatron-c1)
* [3. Experimental Plan:](#3-experimental-plan)
    * [Current Infrastructure](#current-infrastructure)
    * [Experimental Setup Summary](#experimental-setup-summary)

<!-- vim-markdown-toc -->

## 1. Bimo CICD Discussion

**GitHub Actions vs Traditional Infrastructure**
- GitHub Actions removes the need for dedicated infrastructure. Jenkins requires servers; GitHub Actions does not. The free tier has limits on concurrent jobs and build minutes.
- The automation work remains unchanged. Bimo confirmed developers still write the pipeline scripts. The complexity of CI/CD automation has not been eliminated—only the infrastructure burden.
- No existing pipeline scripts for GNB, rApp, or O2-related builds. These must be written from scratch.

---

## 2. O-RU Integration Status

## Summary Status

| Software   | Vendor   | PTP Mode   | Status      | Deadline   |
| ---------- | -------- | ------- | --------    | ---------- |
| OAI gNB    | LiteON   | C3      | Done        | Oct 24     |
| OAI gNB    | Pegatron | C3      | Ongoing     | Oct 29     |
| OAI gNB    | Foxconn  | C3      | Ongoing     | ~~Oct 24~~ TBD     |
| srsRAN     | LiteON   | C3      | Blocked     | Oct 30     |


| Worker       | vCPU | Mem | NIC | Context |
| ---          | --- | --- | --- | --      |
| worker-rt-00 |  32   |     |  Intel    |   Newton, Dell R750      |
| worker-rt-01 |   36  |     |   Intel  |   Supermicro       |
| laovisier | 36    |     |  Intel   |  Lavoisier,Supermicro       |

### OAI gNB - LiteON (C3)

> **Worker**: RT-00 \
> **Status**: SUCCESS - GNB operational \
> **Deadline**: Oct 24

**Control Plane**: OK\
**User Plane**: Fixed (was crashing on data plane usage)\

**Setup Details**
- OS Setup: Automated
- Deployment & Config: User YMA

**Issues Resolved**
- Fixed SR-IOV boot loop
- Added `iommu=pt` kernel parameter
- Fixed CPU isolation configuration
- Fixed PTP synchronization issues

| Issue | Root Cause | Solution |
|-------|------------|----------|
| Node boot loop | Missing `iommu=pt` kernel parameter | Added `iommu=pt` to GRUB |
| SR-IOV VF not created | Kernel parameter validation loop | Added missing IOMMU parameter |
| VF mailbox timeout | MTU mismatch (9600 vs 9216) | Aligned MTU to 9216 on both sides |
| PTP sync failure | `phc2sys` couldn't find `ptp4l` socket | Added `uds_address` to ptp4l.conf |
| GNB timing errors | CPU not properly isolated | Fixed kubelet `reservedSystemCPUs` config |
| System SSH hang | CPU allocation deadlock | Aligned kubelet CPU reservation with kernel isolation |
| Pod scheduling failure | Insufficient allocatable CPUs | Reduced pod CPU request from 20 to 16 |

---

### OAI gNB - Pegatron (C3)
**Worker**: Laovisier
**Status**: Started
**Deadline**: Oct 31

- **Control Plane**: OK
- **User Plane**: OK

**Setup Details**
- OS Setup: Manual by Ming
- Deployment & Config: User Ming

**Actions Required**
- Physical cable reconfiguration needed -- **Done**
- Allocate CPU according to isolation on GRUB -- **DONE**
- Fixed SR-IOV boot loop
- Added `iommu=pt` kernel parameter
- Fix crash issue

---

### srsRAN - LiteON (C3)
**Worker**: TBD
**Status**: Blocked - awaiting srsRAN support
**Deadline**: Oct 30

- **Control Plane**: Pending
- **User Plane**: Pending

**Setup Details**
- OS Setup: TBD
- Deployment & Config: TBD

**Blocking Issues**
- Multus network implementation needed
- Git issue opened (Oct 21)
- Email sent to srsRAN team (Oct 21)

---

### OAI gNB - LiteON (C1)
**Worker**: TBD
**Status**: SUCCESS - GNB operational
**Deadline**: Oct 24

- **Control Plane**: Pending
- **User Plane**: Pending

**Setup Details**
- OS Setup: Manual - oai72_su
- Deployment & Config: Manual - oai72_su

**Issues Resolved**
- Fixed SR-IOV boot loop
- Added `iommu=pt` kernel parameter
- Fixed CPU isolation configuration
- Fixed PTP synchronization issues

---

### OAI gNB - Pegatron (C1)
**Worker**: TBD
**Status**: Not started - physical connection needed
**Deadline**: Oct 22

**Control Plane**: Pending
**User Plane**: OK

**Setup Details**
- OS Setup: TBD
- Deployment & Config: TBD

**Actions Required**
- Change

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

