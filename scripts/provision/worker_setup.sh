#!/bin/bash

set -e

# Default values
MASTER_IP=""
JOIN_TOKEN=""
JOIN_HASH=""
HUGEPAGE_SIZE="1G"
HUGEPAGE_COUNT="8"
RT_KERNEL="true"
SRIOV_ENABLE="true"
VFIO_ENABLE="true"
RUNTIME="crio"
ROLLBACK="false"
ROLLBACK_RT="false"

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --master-ip IP         Kubernetes master node IP (required for join)"
    echo "  --join-token TOKEN     Kubernetes join token (required for join)"
    echo "  --join-hash HASH       CA cert hash (required for join)"
    echo "  --hugepage-size SIZE   Hugepage size: 2M or 1G (default: $HUGEPAGE_SIZE)"
    echo "  --hugepage-count NUM   Number of hugepages (default: $HUGEPAGE_COUNT)"
    echo "  --runtime crio|containerd Container runtime (default: $RUNTIME)"
    echo "  --disable-rt           Skip RT kernel installation"
    echo "  --disable-sriov        Skip SR-IOV configuration"
    echo "  --disable-vfio         Skip VFIO configuration"
    echo "  --rollback             Remove Kubernetes worker components only"
    echo "  --rollback-rt          Full rollback including RT kernel"
    echo "  --help                 Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --master-ip 192.168.1.100 --join-token abc123... --join-hash sha256:def456..."
    echo "  $0 --hugepage-size 2M --hugepage-count 1024 --disable-rt"
    echo "  $0 --rollback-rt"
    echo ""
    echo "To get join parameters from master, run on master:"
    echo "  kubeadm token create --print-join-command"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --master-ip)
            MASTER_IP="$2"
            shift 2
            ;;
        --join-token)
            JOIN_TOKEN="$2"
            shift 2
            ;;
        --join-hash)
            JOIN_HASH="$2"
            shift 2
            ;;
        --hugepage-size)
            HUGEPAGE_SIZE="$2"
            shift 2
            ;;
        --hugepage-count)
            HUGEPAGE_COUNT="$2"
            shift 2
            ;;
        --runtime)
            RUNTIME="$2"
            shift 2
            ;;
        --disable-rt)
            RT_KERNEL="false"
            shift
            ;;
        --disable-sriov)
            SRIOV_ENABLE="false"
            shift
            ;;
        --disable-vfio)
            VFIO_ENABLE="false"
            shift
            ;;
        --rollback)
            ROLLBACK="true"
            shift
            ;;
        --rollback-rt)
            ROLLBACK_RT="true"
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# System checker function
check_system_state() {
    echo "Checking system state..."
    local issues=0
    
    # Check for existing Kubernetes
    if command -v kubelet >/dev/null 2>&1; then
        echo "WARNING: kubelet already installed"
        ((issues++))
    fi
    
    # Check for RT kernel
    if uname -r | grep -q rt; then
        echo "INFO: RT kernel already running: $(uname -r)"
    fi
    
    # Check for existing container runtime
    if systemctl is-active --quiet crio 2>/dev/null; then
        echo "WARNING: CRI-O is running"
        ((issues++))
    fi
    
    if systemctl is-active --quiet containerd 2>/dev/null; then
        echo "WARNING: containerd is running"
        ((issues++))
    fi
    
    # Check hugepages
    if [ -d /sys/kernel/mm/hugepages ]; then
        echo "INFO: Hugepages support detected"
        for hp in /sys/kernel/mm/hugepages/hugepages-*; do
            if [ -d "$hp" ]; then
                size=$(basename "$hp" | sed 's/hugepages-//' | sed 's/kB//')
                nr=$(cat "$hp/nr_hugepages" 2>/dev/null || echo "0")
                echo "  - $(($size/1024))MB hugepages: $nr allocated"
            fi
        done
    fi
    
    # Check SR-IOV capability
    if lspci | grep -i "virtual function" >/dev/null 2>&1; then
        echo "INFO: SR-IOV VFs detected"
        lspci | grep -i "virtual function" | wc -l | xargs echo "  - VF count:"
    fi
    
    if [ $issues -gt 0 ]; then
        echo "System has existing components ($issues issues detected)"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "System ready for configuration"
    fi
}

# Full rollback function
perform_full_rollback() {
    echo "Performing full rollback including RT kernel..."
    
    # Remove Kubernetes components
    perform_k8s_rollback
    
    # Remove RT kernel packages
    dnf remove -y kernel-rt kernel-rt-core kernel-rt-modules 2>/dev/null || true
    
    # Reset GRUB to default kernel
    if [ -f /etc/default/grub.bak ]; then
        mv /etc/default/grub.bak /etc/default/grub
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
    
    # Remove hugepages configuration
    if [ -f /etc/systemd/system/hugepages.service ]; then
        systemctl stop hugepages.service 2>/dev/null || true
        systemctl disable hugepages.service 2>/dev/null || true
        rm -f /etc/systemd/system/hugepages.service
    fi
    
    # Reset SR-IOV
    reset_sriov_config
    
    # Remove VFIO modules
    if [ -f /etc/modprobe.d/vfio.conf ]; then
        rm -f /etc/modprobe.d/vfio.conf
        rm -f /etc/modules-load.d/vfio.conf
    fi
    
    # Reset kernel parameters
    if [ -f /etc/sysctl.d/99-rt-worker.conf ]; then
        rm -f /etc/sysctl.d/99-rt-worker.conf
    fi
    
    echo "Full rollback complete. Reboot required to use standard kernel."
    exit 0
}

# Kubernetes worker rollback
perform_k8s_rollback() {
    echo "Rolling back Kubernetes worker components..."
    
    # Stop services
    systemctl stop kubelet 2>/dev/null || true
    systemctl disable kubelet 2>/dev/null || true
    systemctl stop crio 2>/dev/null || true
    systemctl disable crio 2>/dev/null || true
    systemctl stop containerd 2>/dev/null || true
    systemctl disable containerd 2>/dev/null || true
    
    # Remove packages
    dnf remove -y kubelet kubeadm kubectl cri-o cri-tools containerd.io 2>/dev/null || true
    
    # Clean configuration
    rm -rf /etc/kubernetes
    rm -rf /var/lib/kubelet
    rm -rf /var/lib/crio
    rm -rf /var/lib/containerd
    rm -rf /etc/crio
    rm -rf /etc/containerd
    rm -rf /etc/cni
    rm -rf /var/lib/cni
    rm -f /etc/yum.repos.d/kubernetes.repo
    rm -f /etc/yum.repos.d/devel:kubic:libcontainers:stable*.repo
    rm -f /etc/yum.repos.d/docker-ce.repo
    
    # Clean network settings
    rm -f /etc/sysctl.d/k8s.conf
    rm -f /etc/modules-load.d/k8s.conf
    
    if [ "$ROLLBACK" = "true" ]; then
        echo "Kubernetes worker rollback complete."
        exit 0
    fi
}

# SR-IOV configuration functions
configure_sriov() {
    if [ "$SRIOV_ENABLE" = "false" ]; then
        echo "SR-IOV configuration skipped"
        return
    fi
    
    echo "Configuring SR-IOV..."
    
    # Enable IOMMU in kernel parameters
    GRUB_PARAMS="intel_iommu=on iommu=pt"
    
    # Find SR-IOV capable devices
    echo "Detecting SR-IOV capable devices..."
    for dev in /sys/class/net/*; do
        if [ -f "$dev/device/sriov_totalvfs" ]; then
            devname=$(basename "$dev")
            totalvfs=$(cat "$dev/device/sriov_totalvfs")
            if [ "$totalvfs" -gt 0 ]; then
                echo "  - $devname: supports $totalvfs VFs"
                
                # Enable VFs (configure 4 VFs per PF as example)
                vf_count=$((totalvfs > 4 ? 4 : totalvfs))
                echo "$vf_count" > "$dev/device/sriov_numvfs" 2>/dev/null || true
                echo "    Enabled $vf_count VFs"
            fi
        fi
    done
    
    # Create SR-IOV persistence service
    cat <<EOF > /etc/systemd/system/sriov-setup.service
[Unit]
Description=SR-IOV VF Setup
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'for dev in /sys/class/net/*/device/sriov_totalvfs; do [ -f "\$dev" ] && devpath=\$(dirname "\$dev") && totalvfs=\$(cat "\$dev") && [ "\$totalvfs" -gt 0 ] && echo \$((\$totalvfs > 4 ? 4 : \$totalvfs)) > "\$devpath/sriov_numvfs" 2>/dev/null || true; done'

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable sriov-setup.service
}

reset_sriov_config() {
    echo "Resetting SR-IOV configuration..."
    
    # Disable all VFs
    for dev in /sys/class/net/*/device/sriov_numvfs; do
        if [ -f "$dev" ]; then
            echo 0 > "$dev" 2>/dev/null || true
        fi
    done
    
    # Remove service
    if [ -f /etc/systemd/system/sriov-setup.service ]; then
        systemctl stop sriov-setup.service 2>/dev/null || true
        systemctl disable sriov-setup.service 2>/dev/null || true
        rm -f /etc/systemd/system/sriov-setup.service
    fi
}

# VFIO configuration
configure_vfio() {
    if [ "$VFIO_ENABLE" = "false" ]; then
        echo "VFIO configuration skipped"
        return
    fi
    
    echo "Configuring VFIO..."
    
    # Enable VFIO modules
    cat <<EOF > /etc/modules-load.d/vfio.conf
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
EOF
    
    # Configure VFIO
    cat <<EOF > /etc/modprobe.d/vfio.conf
# VFIO configuration for SR-IOV
options vfio enable_unsafe_noiommu_mode=1
options vfio_iommu_type1 allow_unsafe_interrupts=1
EOF
    
    # Load modules immediately
    modprobe vfio 2>/dev/null || true
    modprobe vfio_iommu_type1 2>/dev/null || true
    modprobe vfio_pci 2>/dev/null || true
}

# Hugepages configuration
configure_hugepages() {
    echo "Configuring hugepages: ${HUGEPAGE_COUNT} x ${HUGEPAGE_SIZE}"
    
    # Calculate hugepage parameters
    case $HUGEPAGE_SIZE in
        "2M")
            HP_SIZE_KB=2048
            HP_PARAM="hugepagesz=2M hugepages=${HUGEPAGE_COUNT}"
            ;;
        "1G")
            HP_SIZE_KB=1048576
            HP_PARAM="hugepagesz=1G hugepages=${HUGEPAGE_COUNT}"
            ;;
        *)
            echo "Unsupported hugepage size: $HUGEPAGE_SIZE"
            exit 1
            ;;
    esac
    
    # Create hugepages mount service
    cat <<EOF > /etc/systemd/system/hugepages.service
[Unit]
Description=Hugepages Setup and Mount
DefaultDependencies=false
After=sysinit.target local-fs.target
Before=basic.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/mkdir -p /mnt/hugepages
ExecStart=/bin/mount -t hugetlbfs hugetlbfs /mnt/hugepages -o pagesize=${HUGEPAGE_SIZE}
ExecStop=/bin/umount /mnt/hugepages

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable hugepages.service
    
    # Add to fstab for persistence
    if ! grep -q "hugetlbfs" /etc/fstab; then
        echo "hugetlbfs /mnt/hugepages hugetlbfs pagesize=${HUGEPAGE_SIZE} 0 0" >> /etc/fstab
    fi
    
    return "$HP_PARAM"
}

# RT kernel installation
install_rt_kernel() {
    if [ "$RT_KERNEL" = "false" ]; then
        echo "RT kernel installation skipped"
        return ""
    fi
    
    echo "Installing RT kernel..."
    
    # Enable RT repositories
    dnf install -y epel-release
    dnf config-manager --enable rt
    
    # Install RT kernel
    dnf install -y kernel-rt kernel-rt-core kernel-rt-modules
    
    # RT kernel parameters
    RT_PARAMS="isolcpus=2-7 nohz_full=2-7 rcu_nocbs=2-7 nosoftlockup"
    
    return "$RT_PARAMS"
}

# Container runtime installation
install_container_runtime() {
    case $RUNTIME in
        "crio")
            echo "Installing CRI-O..."
            export VERSION=1.28
            curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_9_Stream/devel:kubic:libcontainers:stable.repo
            curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:${VERSION}.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:${VERSION}/CentOS_9_Stream/devel:kubic:libcontainers:stable:cri-o:${VERSION}.repo

            dnf install -y cri-o cri-tools

            mkdir -p /etc/crio/crio.conf.d
            cat <<EOF > /etc/crio/crio.conf.d/02-cgroup-manager.conf
[crio.runtime]
conmon_cgroup = "pod"
cgroup_manager = "systemd"
EOF

            systemctl enable --now crio
            echo 'KUBELET_EXTRA_ARGS="--container-runtime-endpoint=unix:///var/run/crio/crio.sock"' > /etc/sysconfig/kubelet
            ;;
        "containerd")
            echo "Installing containerd..."
            dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            dnf install -y containerd.io
            
            mkdir -p /etc/containerd
            containerd config default > /etc/containerd/config.toml
            sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
            systemctl enable --now containerd
            ;;
    esac
}

# Main installation function
perform_installation() {
    echo "Starting RT kernel worker node setup..."
    echo "Configuration:"
    echo "  RT Kernel: $RT_KERNEL"
    echo "  Hugepages: ${HUGEPAGE_COUNT} x ${HUGEPAGE_SIZE}"
    echo "  SR-IOV: $SRIOV_ENABLE"
    echo "  VFIO: $VFIO_ENABLE"
    echo "  Runtime: $RUNTIME"
    if [ -n "$MASTER_IP" ]; then
        echo "  Master IP: $MASTER_IP"
    fi
    echo ""

    # Validate join parameters
    if [ -z "$MASTER_IP" ] || [ -z "$JOIN_TOKEN" ] || [ -z "$JOIN_HASH" ]; then
        echo "ERROR: Master IP, join token, and CA hash are required for worker join"
        echo "Run 'kubeadm token create --print-join-command' on master to get these values"
        exit 1
    fi

    # System preparation
    echo "Preparing system..."
    dnf update -y
    dnf install -y wget curl vim git pciutils

    # Backup GRUB configuration
    cp /etc/default/grub /etc/default/grub.bak

    # Configure hugepages and get parameters
    HP_PARAM=$(configure_hugepages)

    # Install RT kernel and get parameters
    RT_PARAM=""
    if [ "$RT_KERNEL" = "true" ]; then
        RT_PARAM=$(install_rt_kernel)
    fi

    # Configure SR-IOV
    configure_sriov

    # Configure VFIO
    configure_vfio

    # Build kernel parameters
    GRUB_PARAMS="intel_iommu=on iommu=pt"
    [ -n "$HP_PARAM" ] && GRUB_PARAMS="$GRUB_PARAMS $HP_PARAM"
    [ -n "$RT_PARAM" ] && GRUB_PARAMS="$GRUB_PARAMS $RT_PARAM"

    # Update GRUB
    echo "Updating GRUB with parameters: $GRUB_PARAMS"
    sed -i "s/GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"$GRUB_PARAMS /" /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg

    # Configure system for Kubernetes
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    systemctl disable --now firewalld

    # Configure SELinux
    setenforce 0
    sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

    # Enable kernel modules
    cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
sctp
EOF
    modprobe overlay 2>/dev/null || true
    modprobe br_netfilter 2>/dev/null || true
    modprobe sctp 2>/dev/null || true

    # Configure sysctl
    cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.sctp.sctp_mem = 94500000 915000000 927000000
net.sctp.sctp_rmem = 4096 65536 16777216
net.sctp.sctp_wmem = 4096 65536 16777216
EOF

    # RT-specific sysctl settings
    if [ "$RT_KERNEL" = "true" ]; then
        cat <<EOF >> /etc/sysctl.d/99-rt-worker.conf
# RT kernel optimizations
kernel.sched_rt_runtime_us = -1
kernel.sched_rt_period_us = 1000000
vm.stat_interval = 10
kernel.timer_migration = 0
EOF
    fi

    sysctl --system

    # Install container runtime
    install_container_runtime

    # Install Kubernetes
    echo "Installing Kubernetes..."
    cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

    dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
    systemctl enable kubelet

    echo ""
    echo "========================================="
    echo "RT kernel worker node setup complete!"
    echo ""
    echo "REBOOT REQUIRED to activate RT kernel and all configurations."
    echo ""
    echo "After reboot, join the cluster with:"
    echo "kubeadm join $MASTER_IP:6443 --token $JOIN_TOKEN --discovery-token-ca-cert-hash $JOIN_HASH"
    echo ""
    echo "Configuration applied:"
    echo "- RT Kernel: $RT_KERNEL"
    echo "- Hugepages: ${HUGEPAGE_COUNT} x ${HUGEPAGE_SIZE}"
    echo "- SR-IOV: $SRIOV_ENABLE"
    echo "- VFIO: $VFIO_ENABLE"
    echo "- Runtime: $RUNTIME"
    echo "========================================="

    # Create post-reboot join script
    cat <<EOF > /root/join-cluster.sh
#!/bin/bash
# Auto-generated cluster join script
echo "Joining Kubernetes cluster..."
kubeadm join $MASTER_IP:6443 --token $JOIN_TOKEN --discovery-token-ca-cert-hash $JOIN_HASH

if [ \$? -eq 0 ]; then
    echo "Successfully joined cluster!"
    echo "Node status:"
    kubectl --kubeconfig /etc/kubernetes/kubelet.conf get nodes
else
    echo "Failed to join cluster. Check network connectivity to master."
fi
EOF
    chmod +x /root/join-cluster.sh

    echo ""
    echo "After reboot, run: /root/join-cluster.sh"
}

# Main execution logic
if [ "$ROLLBACK_RT" = "true" ]; then
    perform_full_rollback
elif [ "$ROLLBACK" = "true" ]; then
    perform_k8s_rollback
else
    check_system_state
    perform_installation
fi
