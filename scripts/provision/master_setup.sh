#!/bin/bash
# RHEL 9.4 Kubernetes Master Node Setup Script
# Enhanced with system checks, rollback, and configurable parameters

set -e

# Default values
API_ADDRESS=""  # Empty means auto-detect primary interface
POD_NETWORK="10.244.0.0/16"
SERVICE_NETWORK="10.96.0.0/12"
SINGLE_NODE="true"
RUNTIME="crio"
ROLLBACK="false"

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --api-address IP       API server advertise address (default: auto-detect)"
    echo "  --pod-network CIDR     Pod network CIDR (default: $POD_NETWORK)"
    echo "  --service-network CIDR Service network CIDR (default: $SERVICE_NETWORK)"
    echo "  --runtime crio|containerd Container runtime (default: $RUNTIME)"
    echo "  --multi-node          Setup multi-node cluster (keeps taints)"
    echo "  --rollback            Remove all Kubernetes components"
    echo "  --help                Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --api-address 192.168.1.100"
    echo "  $0 --runtime containerd --multi-node"
    echo "  $0 --rollback"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --api-address)
            API_ADDRESS="$2"
            shift 2
            ;;
        --pod-network)
            POD_NETWORK="$2"
            shift 2
            ;;
        --service-network)
            SERVICE_NETWORK="$2"
            shift 2
            ;;
        --runtime)
            RUNTIME="$2"
            shift 2
            ;;
        --multi-node)
            SINGLE_NODE="false"
            shift
            ;;
        --rollback)
            ROLLBACK="true"
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
    if command -v kubectl >/dev/null 2>&1; then
        echo "WARNING: kubectl already installed"
        ((issues++))
    fi
    
    if systemctl is-active --quiet kubelet 2>/dev/null; then
        echo "WARNING: kubelet service is running"
        ((issues++))
    fi
    
    # Check for container runtimes
    if systemctl is-active --quiet crio 2>/dev/null; then
        echo "WARNING: CRI-O is running"
        ((issues++))
    fi
    
    if systemctl is-active --quiet containerd 2>/dev/null; then
        echo "WARNING: containerd is running"
        ((issues++))
    fi
    
    # Check for existing cluster
    if [ -f /etc/kubernetes/admin.conf ]; then
        echo "WARNING: Existing Kubernetes configuration found"
        ((issues++))
    fi
    
    # Check network modifications
    if [ -f /etc/sysctl.d/k8s.conf ]; then
        echo "WARNING: Kubernetes sysctl settings detected"
        ((issues++))
    fi
    
    # Check for CNI remnants
    if [ -d /etc/cni/net.d ] && [ "$(ls -A /etc/cni/net.d 2>/dev/null)" ]; then
        echo "WARNING: CNI configuration files exist"
        ((issues++))
    fi
    
    if [ $issues -gt 0 ]; then
        echo "System appears to have existing Kubernetes components ($issues issues detected)"
        echo "Use --rollback to clean the system first, or proceed with caution"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "System appears clean for Kubernetes installation"
    fi
}

# Rollback function
perform_rollback() {
    echo "Rolling back system to generic Linux state..."
    
    # Stop and disable services
    systemctl stop kubelet 2>/dev/null || true
    systemctl disable kubelet 2>/dev/null || true
    systemctl stop crio 2>/dev/null || true
    systemctl disable crio 2>/dev/null || true
    systemctl stop containerd 2>/dev/null || true
    systemctl disable containerd 2>/dev/null || true
    
    # Reset kubeadm
    kubeadm reset -f 2>/dev/null || true
    
    # Remove Kubernetes packages
    dnf remove -y kubelet kubeadm kubectl cri-o cri-tools containerd.io 2>/dev/null || true
    
    # Remove repositories
    rm -f /etc/yum.repos.d/kubernetes.repo
    rm -f /etc/yum.repos.d/devel:kubic:libcontainers:stable*.repo
    rm -f /etc/yum.repos.d/docker-ce.repo
    
    # Clean configuration files
    rm -rf /etc/kubernetes
    rm -rf /var/lib/kubelet
    rm -rf /var/lib/crio
    rm -rf /var/lib/containerd
    rm -rf /etc/crio
    rm -rf /etc/containerd
    rm -rf $HOME/.kube
    rm -rf /etc/cni
    rm -rf /var/lib/cni
    
    # Remove network configuration
    rm -f /etc/sysctl.d/k8s.conf
    rm -f /etc/modules-load.d/k8s.conf
    
    # Remove Cilium binary
    rm -f /usr/local/bin/cilium
    
    # Restore original settings
    if [ -f /etc/selinux/config.bak ]; then
        mv /etc/selinux/config.bak /etc/selinux/config
    else
        sed -i 's/^SELINUX=permissive$/SELINUX=enforcing/' /etc/selinux/config 2>/dev/null || true
    fi
    
    # Re-enable swap and firewall
    systemctl enable --now firewalld 2>/dev/null || true
    if grep -q "^#.*swap" /etc/fstab; then
        sed -i '/swap/ s/^#//' /etc/fstab
        swapon -a 2>/dev/null || true
    fi
    
    # Clean iptables rules
    iptables -F 2>/dev/null || true
    iptables -t nat -F 2>/dev/null || true
    iptables -t mangle -F 2>/dev/null || true
    iptables -X 2>/dev/null || true
    
    echo "Rollback complete. System restored to generic Linux state."
    echo "Reboot recommended to ensure all changes take effect."
    exit 0
}

# Container runtime installation functions
install_crio() {
    echo "Installing CRI-O..."
    export VERSION=1.28
    curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_9_Stream/devel:kubic:libcontainers:stable.repo
    curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:${VERSION}.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:${VERSION}/CentOS_9_Stream/devel:kubic:libcontainers:stable:cri-o:${VERSION}.repo

    dnf install -y cri-o cri-tools

    # Configure CRI-O
    mkdir -p /etc/crio/crio.conf.d
    cat <<EOF > /etc/crio/crio.conf.d/02-cgroup-manager.conf
[crio.runtime]
conmon_cgroup = "pod"
cgroup_manager = "systemd"
EOF

    systemctl enable --now crio
    echo 'KUBELET_EXTRA_ARGS="--container-runtime-endpoint=unix:///var/run/crio/crio.sock"' > /etc/sysconfig/kubelet
}

install_containerd() {
    echo "Installing containerd..."
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y containerd.io
    
    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl enable --now containerd
}

# Main installation function
perform_installation() {
    echo "Starting Kubernetes installation..."
    echo "Configuration:"
    echo "  Runtime: $RUNTIME"
    echo "  Pod Network: $POD_NETWORK"
    echo "  Service Network: $SERVICE_NETWORK"
    echo "  Single Node: $SINGLE_NODE"
    if [ -n "$API_ADDRESS" ]; then
        echo "  API Address: $API_ADDRESS:6443"
    else
        echo "  API Address: auto-detect:6443"
    fi
    echo ""

    # System preparation
    echo "Preparing system..."
    dnf update -y
    dnf install -y wget curl vim git

    # Backup and disable swap/firewall
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    systemctl disable --now firewalld

    # Configure SELinux
    cp /etc/selinux/config /etc/selinux/config.bak 2>/dev/null || true
    setenforce 0
    sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

    # Install container runtime
    case $RUNTIME in
        "crio")
            install_crio
            CRI_SOCKET="unix:///var/run/crio/crio.sock"
            ;;
        "containerd")
            install_containerd
            CRI_SOCKET="unix:///var/run/containerd/containerd.sock"
            ;;
        *)
            echo "Unsupported runtime: $RUNTIME"
            exit 1
            ;;
    esac

    # Enable kernel modules
    cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
sctp
EOF
    modprobe overlay
    modprobe br_netfilter
    modprobe sctp

    # Configure sysctl
    cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.sctp.sctp_mem = 94500000 915000000 927000000
net.sctp.sctp_rmem = 4096 65536 16777216
net.sctp.sctp_wmem = 4096 65536 16777216
EOF
    sysctl --system

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

    # Build kubeadm init command
    KUBEADM_CMD="kubeadm init --pod-network-cidr=$POD_NETWORK --service-cidr=$SERVICE_NETWORK --cri-socket=$CRI_SOCKET"
    
    if [ -n "$API_ADDRESS" ]; then
        KUBEADM_CMD="$KUBEADM_CMD --apiserver-advertise-address=$API_ADDRESS"
        echo "API server will advertise on: $API_ADDRESS:6443"
    else
        echo "API server will auto-detect primary interface for 6443"
    fi

    # Initialize Kubernetes cluster
    echo "Initializing Kubernetes cluster..."
    eval $KUBEADM_CMD

    # Configure kubectl
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config

    # Handle single-node setup
    if [ "$SINGLE_NODE" = "true" ]; then
        kubectl taint nodes --all node-role.kubernetes.io/control-plane-
        echo "Configured as single-node cluster"
    fi

    # Install Cilium CNI with SCTP support
    echo "Installing Cilium CNI..."
    curl -L https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz | tar -xz
    mv cilium /usr/local/bin/
    cilium install --config enable-sctp=true

    echo "Waiting for Cilium to be ready..."
    cilium status --wait

    # Install Multus CNI (thick deployment)
    echo "Installing Multus CNI (thick deployment)..."
    kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

    # Wait for Multus to be ready
    kubectl wait --for=condition=ready pod -l app=multus -n kube-system --timeout=300s

    # Install OpenEBS
    echo "Installing OpenEBS..."
    kubectl apply -f https://openebs.github.io/charts/openebs-operator.yaml

    # Wait for OpenEBS pods to be ready
    kubectl wait --for=condition=ready pod -l app=openebs -n openebs --timeout=300s

    # Set OpenEBS as default storage class
    kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

    echo ""
    echo "========================================="
    echo "Setup complete! Kubernetes master node ready."
    echo "Configuration summary:"
    echo "- Runtime: $RUNTIME"
    echo "- Pod Network: $POD_NETWORK"
    echo "- Service Network: $SERVICE_NETWORK"
    if [ -n "$API_ADDRESS" ]; then
        echo "- API Server: $API_ADDRESS:6443"
    else
        echo "- API Server: $(hostname -I | awk '{print $1}'):6443"
    fi
    echo "- Single Node: $SINGLE_NODE"
    echo ""
    echo "Components installed:"
    echo "- Kubernetes v1.28"
    echo "- Cilium CNI with SCTP enabled"
    echo "- Multus CNI (thick deployment)"
    echo "- OpenEBS storage (default)"
    echo "========================================="
    echo ""

    # Display cluster status
    echo "Cluster status:"
    kubectl get nodes
    echo ""
    echo "System pods:"
    kubectl get pods --all-namespaces
}

# Main execution logic
if [ "$ROLLBACK" = "true" ]; then
    perform_rollback
else
    check_system_state
    perform_installation
fi
