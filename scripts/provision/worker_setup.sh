#!/bin/bash
set -euo pipefail

# Configuration variables
MASTER_IP="${MASTER_IP:-}"
JOIN_TOKEN="${JOIN_TOKEN:-}"
JOIN_HASH="${JOIN_HASH:-}"
HUGEPAGE_SIZE="${HUGEPAGE_SIZE:-1G}"
HUGEPAGE_COUNT="${HUGEPAGE_COUNT:-8}"
HUGEPAGE_2M_COUNT="${HUGEPAGE_2M_COUNT:-0}"  # Additional 2M hugepages
HOUSEKEEPING_CPUS="${HOUSEKEEPING_CPUS:-5}"  # First N CPUs for K8s
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-crio}"
ENABLE_RT="${ENABLE_RT:-true}"
ENABLE_VFIO="${ENABLE_VFIO:-true}"
AUTO_REBOOT="${AUTO_REBOOT:-false}"
ROLLBACK="${ROLLBACK:-false}"

# Red Hat registration
RH_ORG_ID="${RH_ORG_ID:-}"
RH_ACTIVATION_KEY="${RH_ACTIVATION_KEY:-}"

# Version configuration
CRIO_VERSION="${CRIO_VERSION:-1.28}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.28}"

readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="/var/log/${SCRIPT_NAME%.*}.log"

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OAI gNodeB RT Worker Node Setup for RHEL 9.5
Setup → Join Cluster → Reboot to Activate RT Kernel

Options:
    --master-ip IP              Kubernetes master IP
    --join-token TOKEN          Kubernetes join token
    --join-hash HASH           CA cert hash
    --hugepage-size SIZE       Primary hugepage size: 2M or 1G (default: 1G)
    --hugepage-count NUM       Number of primary hugepages (default: 8)
    --hugepage-2m-count NUM    Additional 2M hugepages (default: 0)
    --housekeeping-cpus NUM    CPUs reserved for K8s (default: 5)
    --runtime RUNTIME          Container runtime: crio|containerd (default: crio)
    --crio-version VER         CRI-O version (default: 1.28)
    --k8s-version VER          Kubernetes version (default: v1.28)
    --rh-org-id ID             Red Hat organization ID
    --rh-activation-key KEY    Red Hat activation key
    --auto-reboot              Reboot automatically after setup
    --disable-rt               Skip RT kernel installation
    --disable-vfio             Skip VFIO configuration
    --rollback                 Rollback configuration to standard setup
    --help                     Show this help

Examples:
    # Basic RT setup with Red Hat registration
    $0 --rh-org-id 12345 --rh-activation-key mykey123

    # Full automated worker setup
    $0 --master-ip 192.168.1.100 --join-token abc123... --join-hash sha256:def456... \\
       --rh-org-id 12345 --rh-activation-key mykey123 --auto-reboot

    # Advanced hugepages configuration
    $0 --hugepage-size 1G --hugepage-count 32 --hugepage-2m-count 1024 \\
       --housekeeping-cpus 8 --master-ip 192.168.1.100 --join-token ... --join-hash ...


    # Rollback to standard configuration
    $0 --rollback

Note: Enhanced RT kernel parameters for maximum performance
      SR-IOV device configuration handled by Multus SR-IOV CNI
EOF
    exit 0
}

# Add this function after perform_rollback()
perform_cluster_rollback() {
    log "INFO" "Removing worker node from cluster"

    local node_name=$(hostname)

    kubectl drain "$node_name" --ignore-daemonsets --delete-emptydir-data

    # Try to remove node from cluster if kubectl is available
    if [[ -f /etc/kubernetes/kubelet.conf ]]; then
        #export KUBECONFIG=/etc/kubernetes/kubelet.conf
        kubectl delete node "$node_name" --ignore-not-found=true 2>/dev/null || true
    fi

    # Stop services
    systemctl stop kubelet crio containerd 2>/dev/null || true

    # Reset kubeadm configuration
    kubeadm reset --force 2>/dev/null || true

    # Clean iptables rules
    iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X 2>/dev/null || true

    # Remove remaining configs
    rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/crio /var/lib/containerd
    rm -rf /etc/cni /var/lib/cni /run/flannel /etc/crio /etc/containerd

    # Reset network
    ip link delete cni0 2>/dev/null || true
    ip link delete flannel.1 2>/dev/null || true

    log "INFO" "Node removed from cluster"
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --master-ip) MASTER_IP="$2"; shift 2 ;;
            --join-token) JOIN_TOKEN="$2"; shift 2 ;;
            --join-hash) JOIN_HASH="$2"; shift 2 ;;
            --hugepage-size) HUGEPAGE_SIZE="$2"; shift 2 ;;
            --hugepage-count) HUGEPAGE_COUNT="$2"; shift 2 ;;
            --hugepage-2m-count) HUGEPAGE_2M_COUNT="$2"; shift 2 ;;
            --housekeeping-cpus) HOUSEKEEPING_CPUS="$2"; shift 2 ;;
            --runtime) CONTAINER_RUNTIME="$2"; shift 2 ;;
            --crio-version) CRIO_VERSION="$2"; shift 2 ;;
            --k8s-version) KUBERNETES_VERSION="$2"; shift 2 ;;
            --rh-org-id) RH_ORG_ID="$2"; shift 2 ;;
            --rh-activation-key) RH_ACTIVATION_KEY="$2"; shift 2 ;;
            --auto-reboot) AUTO_REBOOT="true"; shift ;;
            --disable-rt) ENABLE_RT="false"; shift ;;
            --disable-vfio) ENABLE_VFIO="false"; shift ;;
            --rollback) ROLLBACK="true"; shift ;;
	        --rollback-cluster) ROLLBACK_CLUSTER="true"; shift ;;
            --help) usage ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done
}

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" | tee -a "$LOG_FILE"
}

die() {
    log "ERROR" "$1"
    exit 1
}

# Calculate isolated CPUs (all CPUs except first N housekeeping)
calculate_isolated_cpus() {
    local total_cpus
    total_cpus=$(nproc)

    if [[ $total_cpus -le $HOUSEKEEPING_CPUS ]]; then
        die "Not enough CPUs: need >$HOUSEKEEPING_CPUS, found $total_cpus"
    fi

    local isolated_start=$HOUSEKEEPING_CPUS
    local isolated_end=$((total_cpus - 1))

    echo "${isolated_start}-${isolated_end}"
}

# Calculate housekeeping CPUs list
calculate_housekeeping_cpus() {
    echo "0-$((HOUSEKEEPING_CPUS-1))"
}

# Rollback function
perform_rollback() {
    log "INFO" "Starting system rollback to standard configuration"

    echo "========================================="
    echo "SYSTEM ROLLBACK - Removing RT Configuration"
    echo "========================================="

    # Reset
    kubeadm reset --force || true

    # Stop services
    log "INFO" "Stopping services"
    systemctl stop kubelet 2>/dev/null || true
    systemctl disable kubelet 2>/dev/null || true
    systemctl stop crio containerd 2>/dev/null || true
    systemctl disable crio containerd 2>/dev/null || true
    echo "blacklist sctp" >> /etc/modprobe.d/sctp-blacklist.conf || true

    # Reset tuned profile to default
    log "INFO" "Resetting tuned profile"
    if command -v tuned-adm &>/dev/null; then
        tuned-adm profile throughput-performance 2>/dev/null || tuned-adm off
    fi

    # Remove custom tuned profiles
    rm -rf /etc/tuned/oai-realtime /etc/tuned/realtime-variables.conf 2>/dev/null || true

    # Remove RT kernel packages
    log "INFO" "Removing RT kernel packages"
    dnf remove -y kernel-rt kernel-rt-core kernel-rt-modules tuned-profiles-realtime 2>/dev/null || true

    # Remove Kubernetes and container runtime
    log "INFO" "Removing Kubernetes and container runtime"
    dnf remove -y kubelet kubeadm kubectl cri-o containerd.io 2>/dev/null || true

    # Clean configuration files
    log "INFO" "Cleaning configuration files"
    rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/crio /var/lib/containerd
    rm -rf /etc/crio /etc/containerd /etc/cni /var/lib/cni
    rm -f /etc/yum.repos.d/kubernetes.repo /etc/yum.repos.d/cri-o.repo
    rm -f /etc/yum.repos.d/docker-ce.repo
    rm -f /etc/sysconfig/kubelet

    # Clean network and system settings
    rm -f /etc/sysctl.d/k8s.conf /etc/sysctl.d/99-oai-rt.conf
    rm -f /etc/modules-load.d/k8s.conf /etc/modules-load.d/vfio.conf /etc/modules-load.d/sctp.conf
    rm -f /etc/modprobe.d/vfio.conf
    rm -f /etc/security/limits.d/99-oai-rt.conf

    # Unmount and remove hugepages
    umount /mnt/hugepages 2>/dev/null || true
    rmdir /mnt/hugepages 2>/dev/null || true
    sed -i '/hugetlbfs/d' /etc/fstab 2>/dev/null || true

    # Reset GRUB to remove RT parameters
    log "INFO" "Resetting GRUB configuration"
    if [[ -f /etc/default/grub.bak ]]; then
        mv /etc/default/grub.bak /etc/default/grub
        grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        # Remove RT-specific kernel parameters from current GRUB config
        sed -i 's/isolcpus=[^ ]* //g; s/nohz_full=[^ ]* //g; s/nohz=on //g; s/rcu_nocbs=[^ ]* //g' /etc/default/grub
        sed -i 's/kthread_cpus=[^ ]* //g; s/irqaffinity=[^ ]* //g; s/rcu_nocb_poll //g' /etc/default/grub
        sed -i 's/intel_pstate=disable //g; s/nosoftlockup //g; s/hugepagesz=[^ ]* //g; s/hugepages=[^ ]* //g' /etc/default/grub
        sed -i 's/default_hugepagesz=[^ ]* //g; s/mitigations=off //g; s/processor\.max_cstate=[^ ]* //g' /etc/default/grub
        sed -i 's/idle=poll //g; s/intel_idle\.max_cstate=[^ ]* //g; s/skew_tick=[^ ]* //g' /etc/default/grub
        sed -i 's/tsc=nowatchdog //g; s/softlockup_panic=[^ ]* //g; s/audit=[^ ]* //g; s/mce=off //g' /etc/default/grub
        sed -i 's/intel_iommu=on //g; s/iommu=pt //g; s/numa=off //g; s/vfio-pci\.enable_sriov=[^ ]* //g' /etc/default/grub
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi

    # Re-enable swap if it exists
    if grep -q "swap" /etc/fstab; then
        sed -i '/swap/s/^#//' /etc/fstab
        swapon -a 2>/dev/null || true
    fi

    # Re-enable SELinux
    setenforce 1 2>/dev/null || true
    sed -i 's/^SELINUX=permissive$/SELINUX=enforcing/' /etc/selinux/config

    # Re-enable firewalld
    systemctl enable --now firewalld 2>/dev/null || true

    # Apply system defaults
    sysctl --system

    # Switch to standard kernel if running RT
    if [[ "$(uname -r)" == *"+rt"* ]]; then
        log "INFO" "Running RT kernel, switching default to standard"

        local standard_kernel=$(grubby --info=ALL | grep "^kernel=" | grep -v "rt" | head -1 | cut -d'"' -f2)

        if [[ -z "$standard_kernel" ]]; then
            dnf install -y kernel 2>/dev/null || die "No standard kernel available"
            standard_kernel=$(grubby --info=ALL | grep "^kernel=" | grep -v "rt" | head -1 | cut -d'"' -f2)
        fi

        grubby --set-default="$standard_kernel"
        log "INFO" "Default kernel set to: $(basename $standard_kernel)"
        log "INFO" "Rebooting to standard kernel for cleanup"
        reboot
        exit 0
    fi

    log "INFO" "Running standard kernel, proceeding with cleanup"

    log "INFO" "Rollback completed successfully"
    echo ""
    echo "========================================="
    echo "Rollback Complete!"
    echo "System restored to standard configuration."
    echo "Reboot recommended to activate changes."
    echo "========================================="

    #reboot

    exit 0
}

# Register with Red Hat
register_system() {
    if [[ -n "$RH_ORG_ID" && -n "$RH_ACTIVATION_KEY" ]]; then
        log "INFO" "Registering system with Red Hat"

        subscription-manager register \
            --org="$RH_ORG_ID" \
            --activationkey="$RH_ACTIVATION_KEY" \
            --force || die "Failed to register system"

        subscription-manager attach --auto || die "Failed to attach subscriptions"
        log "INFO" "System registered successfully"
    else
        log "INFO" "Skipping Red Hat registration (no credentials provided)"
        subscription-manager identity &>/dev/null || \
            die "System not registered. Provide --rh-org-id and --rh-activation-key"
    fi
}

# Validate prerequisites
validate_system() {
    log "INFO" "Validating system prerequisites"

    [[ $EUID -eq 0 ]] || die "Must run as root"
    [[ -f /etc/redhat-release ]] || die "Not a RHEL system"

    local rhel_version
    rhel_version=$(grep -oE 'release [0-9]+\.[0-9]+' /etc/redhat-release | cut -d' ' -f2)
    [[ "${rhel_version%%.*}" -eq 9 ]] || die "Requires RHEL 9.x (found: $rhel_version)"

    local total_cpus
    total_cpus=$(nproc)
    log "INFO" "System has $total_cpus CPUs, reserving first $HOUSEKEEPING_CPUS for K8s"

    if [[ -n "$MASTER_IP" ]]; then
        [[ -n "$JOIN_TOKEN" && -n "$JOIN_HASH" ]] || \
            die "JOIN_TOKEN and JOIN_HASH required with MASTER_IP"
        ping -c1 "$MASTER_IP" &>/dev/null || die "Cannot reach master IP: $MASTER_IP"
    fi

    # Validate hugepage sizes
    case "$HUGEPAGE_SIZE" in
        2M|1G) ;;
        *) die "Invalid hugepage size: $HUGEPAGE_SIZE (use 2M or 1G)" ;;
    esac

    # Validate container runtime
    case "$CONTAINER_RUNTIME" in
        crio|containerd) ;;
        *) die "Invalid container runtime: $CONTAINER_RUNTIME (use crio or containerd)" ;;
    esac

    log "INFO" "System validation passed"
}

# Configure RT kernel and tuned profile with enhanced parameters
setup_realtime() {
    log "INFO" "Setting up RT kernel with enhanced performance parameters"

    local isolated_cpus housekeeping_cpus
    isolated_cpus=$(calculate_isolated_cpus)
    housekeeping_cpus=$(calculate_housekeeping_cpus)

    log "INFO" "CPU allocation - Housekeeping: $housekeeping_cpus, Isolated: $isolated_cpus"

    # Backup GRUB configuration
    [[ ! -f /etc/default/grub.bak ]] && cp /etc/default/grub /etc/default/grub.bak

    # Enable RT repository
    subscription-manager repos --enable="rhel-9-for-$(uname -m)-rt-rpms" ||
        die "Failed to enable RT repository"

    # Install RT packages
    dnf install -y kernel-rt kernel-rt-core kernel-rt-modules kernel-rt-modules-extra tuned-profiles-realtime linuxptp.x86_64 ||
        die "Failed to install RT packages"
    # Set RT kernel as default boot option
    log "INFO" "Configuring RT kernel as default boot option"

    # Get the latest RT kernel version
    local rt_kernel_version
    rt_kernel_version=$(rpm -q kernel-rt --last | head -1 | awk '{print $1}' | sed 's/kernel-rt-//')

    if [[ -n "$rt_kernel_version" ]]; then
        # Set RT kernel as default using grubby
        grubby --set-default "/boot/vmlinuz-${rt_kernel_version}+rt" || \
            die "Failed to set RT kernel as default"

        log "INFO" "RT kernel ${rt_kernel_version}+rt set as default boot option"
    else
        log "WARN" "Could not determine RT kernel version"
    fi

    # Configure realtime variables
    cat > /etc/tuned/realtime-variables.conf << EOF
# OAI gNodeB RT configuration with enhanced performance parameters
# Housekeeping CPUs: $housekeeping_cpus (for Kubernetes)
# Isolated CPUs: $isolated_cpus (for RT containers)
isolated_cores=$isolated_cpus
EOF

    # Create enhanced tuned profile with all performance parameters
    mkdir -p /etc/tuned/oai-realtime
    cat > /etc/tuned/oai-realtime/tuned.conf << EOF
[main]
summary=OAI gNodeB RT profile with maximum performance tuning
include=realtime

[bootloader]
# Complete RT kernel command line with all performance optimizations
cmdline_oai=+numa=off isolcpus=managed_irq,\${isolated_cores} nohz_full=\${isolated_cores} nohz=on rcu_nocbs=\${isolated_cores} kthread_cpus=$housekeeping_cpus irqaffinity=$housekeeping_cpus rcu_nocb_poll intel_pstate=disable nosoftlockup hugepagesz=${HUGEPAGE_SIZE} hugepages=${HUGEPAGE_COUNT} hugepagesz=2M hugepages=${HUGEPAGE_2M_COUNT} default_hugepagesz=${HUGEPAGE_SIZE} mitigations=off intel_iommu=on processor.max_cstate=1 idle=poll intel_idle.max_cstate=0 iommu=pt skew_tick=1 tsc=nowatchdog nmi_watchdog=0 softlockup_panic=0 audit=0 mce=off crashkernel=auto vfio-pci.enable_sriov=1

[sysctl]
# Enhanced network optimizations for OAI
net.sctp.sctp_mem = 94500000 915000000 927000000
net.sctp.sctp_rmem = 4096 65536 16777216
net.sctp.sctp_wmem = 4096 65536 16777216
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.netdev_max_backlog = 30000
net.core.netdev_budget = 600

# RT kernel optimizations
kernel.sched_rt_runtime_us = -1
kernel.sched_rt_period_us = 1000000
vm.stat_interval = 10
kernel.hung_task_timeout_secs = 600

# Memory and performance tuning
vm.swappiness = 1
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3
vm.overcommit_memory = 1
vm.zone_reclaim_mode = 0

# Interrupt and timer optimizations
kernel.timer_migration = 0
kernel.sched_migration_cost_ns = 5000000

[script]
script = \${i:PROFILE_DIR}/oai-setup.sh
EOF

    # Create comprehensive setup script
    cat > /etc/tuned/oai-realtime/oai-setup.sh << EOF
#!/bin/bash
# OAI RT setup script with enhanced configuration
case "\$1" in
    start)
        # Setup hugepages mount
        mkdir -p /mnt/hugepages
        if ! mount | grep -q "/mnt/hugepages"; then
            mount -t hugetlbfs hugetlbfs /mnt/hugepages -o pagesize=${HUGEPAGE_SIZE}
        fi

        # Add hugepages to fstab for persistence
        if ! grep -q "hugetlbfs" /etc/fstab; then
            echo "hugetlbfs /mnt/hugepages hugetlbfs pagesize=${HUGEPAGE_SIZE} 0 0" >> /etc/fstab
        fi

        # Set RT priority and memory limits
        if ! grep -q "rtprio" /etc/security/limits.d/99-oai-rt.conf 2>/dev/null; then
            cat > /etc/security/limits.d/99-oai-rt.conf << LIMITS
# RT priority limits for OAI applications
* soft rtprio 99
* hard rtprio 99
* soft memlock unlimited
* hard memlock unlimited
* soft nice -20
* hard nice -20
LIMITS
        fi

        # Configure IRQ affinity for housekeeping CPUs
        echo "$housekeeping_cpus" > /proc/irq/default_smp_affinity 2>/dev/null || true

        # Set CPU frequency governor to performance for housekeeping CPUs
        for cpu in {0..$((HOUSEKEEPING_CPUS-1))}; do
            echo performance > /sys/devices/system/cpu/cpu\$cpu/cpufreq/scaling_governor 2>/dev/null || true
        done
        ;;
    stop)
        umount /mnt/hugepages 2>/dev/null || true
        ;;
esac
EOF

    chmod +x /etc/tuned/oai-realtime/oai-setup.sh

    # Activate profile
    tuned-adm profile oai-realtime
    log "INFO" "Applied oai-realtime tuned profile with enhanced RT parameters"
}

# Configure VFIO kernel modules for SR-IOV support
setup_vfio() {
    [[ "$ENABLE_VFIO" == "true" ]] || return 0

    log "INFO" "Configuring VFIO kernel modules for SR-IOV support"

    # Load VFIO kernel modules needed for SR-IOV
    cat > /etc/modules-load.d/vfio.conf << EOF
# VFIO modules for SR-IOV support with enhanced configuration
# Device configuration handled by Multus SR-IOV CNI
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
EOF

    # Load SCTP related modules
    echo "" >| /etc/modprobe.d/sctp-blacklist.conf || true
    cat > /etc/modules-load.d/sctp.conf << EOF
# Enhanced VFIO configuration for SR-IOV support
sctp
EOF

    # Configure VFIO module parameters with SR-IOV support
    cat > /etc/modprobe.d/vfio.conf << EOF
# Enhanced VFIO configuration for SR-IOV support
# Device configuration handled by Multus SR-IOV CNI
options vfio enable_unsafe_noiommu_mode=1
options vfio_iommu_type1 allow_unsafe_interrupts=1
options vfio_pci enable_sriov=1
options vfio_pci disable_idle_d3=1
EOF

    log "INFO" "VFIO kernel modules configured with SR-IOV support"
}

# Setup repositories with latest templates
setup_repositories() {
    log "INFO" "Setting up container runtime and Kubernetes repositories"

    case "$CONTAINER_RUNTIME" in
        crio)
            # Setup latest CRI-O repository
            cat > /etc/yum.repos.d/cri-o.repo << EOF
[cri-o]
name=CRI-O
baseurl=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v${CRIO_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v${CRIO_VERSION}/rpm/repodata/repomd.xml.key
EOF
            ;;
        containerd)
            # Setup Docker repository for containerd
            dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            ;;
    esac

    # Setup latest Kubernetes repository
    cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

    log "INFO" "Repositories configured for CRI-O ${CRIO_VERSION} and Kubernetes ${KUBERNETES_VERSION}"
}

# Install and configure Kubernetes
setup_kubernetes() {
    log "INFO" "Installing and configuring Kubernetes"

    # Setup repositories first
    setup_repositories

    # System preparation
    log "INFO" "Preparing system for Kubernetes"
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    systemctl disable --now firewalld 2>/dev/null || true
    setenforce 0 2>/dev/null || true
    sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

    # Load kernel modules
    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF

    modprobe overlay br_netfilter sctp ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh nf_conntrack 2>/dev/null || true

    # Enhanced sysctl configuration
    cat > /etc/sysctl.d/k8s.conf << EOF
# Kubernetes networking
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Enhanced networking for RT workloads
net.netfilter.nf_conntrack_max = 1048576
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 65536
net.core.netdev_max_backlog = 16384

# Memory and performance
vm.max_map_count = 262144
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
EOF

    sysctl --system

    # Install container runtime
    case "$CONTAINER_RUNTIME" in
        crio)
            log "INFO" "Installing CRI-O ${CRIO_VERSION}"
            dnf install -y cri-o

            # Enhanced CRI-O configuration for RT workloads
            mkdir -p /etc/crio/crio.conf.d
            cat > /etc/crio/crio.conf.d/02-oai-rt-config.conf << EOF
[crio.runtime]
conmon_cgroup = "pod"
cgroup_manager = "systemd"
default_runtime = "runc"
pids_limit = 16384
log_size_max = 52428800
container_exits_dir = "/var/run/crio/exits"
container_attach_socket_dir = "/var/run/crio"

[crio.runtime.runtimes.runc]
runtime_path = "/usr/bin/runc"
runtime_type = "oci"
runtime_root = "/run/runc"

[crio.image]
pause_image = "registry.k8s.io/pause:3.9"

[crio.network]
cni_default_network = ""
network_dir = "/etc/cni/net.d/"
plugin_dirs = ["/opt/cni/bin/"]
EOF

            systemctl enable --now crio
            log "INFO" "CRI-O configured and started"
            ;;
        containerd)
            log "INFO" "Installing containerd"
            dnf install -y containerd.io

            mkdir -p /etc/containerd
            containerd config default > /etc/containerd/config.toml

            # Enhanced containerd configuration
            sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
            sed -i 's/sandbox_image = .*/sandbox_image = "registry.k8s.io\/pause:3.9"/' /etc/containerd/config.toml

            systemctl enable --now containerd
            log "INFO" "containerd configured and started"
            ;;
    esac

    # Install Kubernetes
    log "INFO" "Installing Kubernetes ${KUBERNETES_VERSION}"
    dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

    # Simplified KUBELET_EXTRA_ARGS
    cat > /etc/sysconfig/kubelet << EOF
KUBELET_EXTRA_ARGS="--config=/var/lib/kubelet/config.yaml"
EOF

    systemctl enable --now kubelet
    log "INFO" "Kubernetes configured with enhanced RT optimizations"
}

# Join cluster immediately (before reboot)
join_cluster_now() {
    log "INFO" "Joining Kubernetes cluster"

    #local isolated_cpus
    #isolated_cpus=$(calculate_isolated_cpus)

    echo ""
    echo "=== Joining OAI gNodeB RT Worker Node ==="
    echo "Current kernel: $(uname -r)"
    #echo "Housekeeping CPUs: $(calculate_housekeeping_cpus)"
    #echo "RT CPUs (after reboot): $isolated_cpus"
    echo "Primary hugepages (after reboot): ${HUGEPAGE_COUNT} x ${HUGEPAGE_SIZE}"
    echo "Secondary hugepages (after reboot): ${HUGEPAGE_2M_COUNT} x 2M"
    echo "Container Runtime: $CONTAINER_RUNTIME ${CRIO_VERSION}"
    echo ""

    if kubeadm join "$MASTER_IP:6443" --token "$JOIN_TOKEN" --discovery-token-ca-cert-hash "$JOIN_HASH"; then
        echo ""
        echo "✓ Successfully joined cluster!"
        echo "Node will be fully RT-capable after reboot."

        # Wait a moment for kubelet to start
        sleep 5

	if [[ -f /etc/kubernetes/kubelet.conf ]]; then
            #export KUBECONFIG=/etc/kubernetes/kubelet.conf

            # Wait for node registration and apply labels
            local node_name=$(hostname)
            sleep 15

            kubectl label node "$node_name" node-role.kubernetes.io/worker="" --overwrite || true
            kubectl label node "$node_name" feature.node.kubernetes.io/network-sriov.capable=true --overwrite || true

            echo "Patch RT Kubelet"
            apply_rt_kubelet_config

            log "INFO" "Node labeled and configured"
        fi

        # Show current cluster status
        echo ""
        echo "Current cluster nodes:"
        kubectl get nodes --kubeconfig /etc/kubernetes/kubelet.conf 2>/dev/null || \
            echo "Node status will be available after kubelet initialization"

        log "INFO" "Successfully joined Kubernetes cluster"
    else
        die "Failed to join cluster. Check connectivity and credentials."
    fi
}

apply_rt_kubelet_config() {
    log "INFO" "Applying RT kubelet configuration from ansible"

    # Count CPU
    local housekeeping_cpus
    housekeeping_cpus=$(calculate_housekeeping_cpus)

    if [[ -f /tmp/kubelet-rt-config.yaml ]]; then
        #cp /tmp/kubelet-rt-config.yaml /var/lib/kubelet/config.yaml
        #reservedSystemCPUs: "$housekeeping_cpus"
        cat /tmp/kubelet-rt-config.yaml >> /var/lib/kubelet/config.yaml
        sed -i "s/@RESERVED_CPU@/$housekeeping_cpus/g" /var/lib/kubelet/config.yaml
        rm /var/lib/kubelet/cpu_manager_state || true
        systemctl restart kubelet
        sleep 10
        log "INFO" "RT kubelet configuration applied"
        log "INFO" "$(cat /var/lib/kubelet/cpu_manager_state || true)"

    else
        log "WARN" "RT kubelet config not provided by ansible"
    fi
}

# Handle reboot process
handle_reboot() {
    if [[ "$ENABLE_RT" != "true" ]]; then
        log "INFO" "RT kernel disabled - no reboot required"
        return 0
    fi

    # local isolated_cpus
    # isolated_cpus=$(calculate_isolated_cpus)

    echo ""
    echo "========================================="
    echo "=== Setup Complete ==="
    echo "========================================="
    echo "Enhanced RT Configuration Summary:"
    echo "  ✓ RT Kernel: Installed with maximum performance tuning"
    echo "  ✓ Primary Hugepages: ${HUGEPAGE_COUNT} x ${HUGEPAGE_SIZE}"
    echo "  ✓ Secondary Hugepages: ${HUGEPAGE_2M_COUNT} x 2M"
    echo "  ✓ NUMA: Single node (numa=off)"
    echo "  ✓ IOMMU: Enabled with passthrough"
    echo "  ✓ SR-IOV: VFIO support enabled"
    echo "  ✓ Performance: Mitigations disabled, idle=poll"
    echo "  ✓ Container Runtime: $CONTAINER_RUNTIME ${CRIO_VERSION}"
    echo "  ✓ Kubernetes: ${KUBERNETES_VERSION} joined cluster"
    echo ""
    echo "Enhanced kernel parameters applied:"
    echo "  • CPU isolation with managed IRQ"
    echo "  • nohz_full and RCU callback offload"
    echo "  • Thread and IRQ affinity optimization"
    echo "  • Power management disabled (C-states, idle)"
    echo "  • Security mitigations disabled for performance"
    echo "  • Audit and MCE subsystems disabled"
    echo ""
    echo "RT kernel activation requires reboot."
    echo "========================================="

}


# Main execution
main() {
    parse_args "$@"

    # Handle rollback first
    if [[ "$ROLLBACK" == "true" ]]; then
        perform_rollback
        return
    fi

    if [[ "${ROLLBACK_CLUSTER:-false}" == "true" ]]; then
        perform_cluster_rollback
        return
    fi

    echo ""
    echo "========================================="
    echo "OAI gNodeB Enhanced RT Worker Node Setup - RHEL 9.5"
    echo "Enhanced with maximum performance kernel parameters"
    echo "========================================="
    log "INFO" "Starting enhanced setup with CPU allocation: first $HOUSEKEEPING_CPUS CPUs for K8s, rest for RT"

    register_system
    validate_system

    if [[ "$ENABLE_RT" == "true" ]]; then
        setup_realtime
    fi

    setup_vfio
    setup_kubernetes

    # Join cluster before reboot
    if [[ -n "$MASTER_IP" ]]; then
        join_cluster_now
    else
        log "INFO" "No master IP provided - skipping cluster join"
        echo "To join cluster later, use:"
        echo "kubeadm join <MASTER_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash <HASH>"
    fi

    handle_reboot
}

# Execute if called directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
