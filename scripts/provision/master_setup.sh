#!/bin/bash
# RHEL 9.4 Kubernetes Master Node Setup
set -e

# Configuration
POD_NETWORK="${POD_NETWORK:-10.128.0.0/14}"
SERVICE_NETWORK="${SERVICE_NETWORK:-10.96.0.0/12}"
RUNTIME="${RUNTIME:-crio}"
CRIO_VERSION="${CRIO_VERSION:-1.28}"
K8S_VERSION="${KUBERNETES_VERSION:-1.28}"
SINGLE_NODE="true"
API_ADDRESS=""
ROLLBACK="false"

readonly LOG_FILE="/var/log/k8s-setup.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" | tee -a "$LOG_FILE"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]
Options:
  --api-address IP       API server address (default: auto-detect)
  --pod-network CIDR     Pod CIDR (default: $POD_NETWORK)
  --service-network CIDR Service CIDR (default: $SERVICE_NETWORK)
  --runtime crio|containerd (default: $RUNTIME)
  --multi-node          Multi-node cluster (keeps taints)
  --crio-version VER    CRI-O version (default: $CRIO_VERSION)
  --k8s-version VER     Kubernetes version (default: $K8S_VERSION)
  --rollback            Remove Kubernetes components
  --help                This message
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --api-address) API_ADDRESS="$2"; shift 2 ;;
        --pod-network) POD_NETWORK="$2"; shift 2 ;;
        --service-network) SERVICE_NETWORK="$2"; shift 2 ;;
        --runtime) RUNTIME="$2"; shift 2 ;;
        --multi-node) SINGLE_NODE="false"; shift ;;
        --crio-version) CRIO_VERSION="$2"; shift 2 ;;
        --k8s-version) K8S_VERSION="$2"; shift 2 ;;
        --rollback) ROLLBACK="true"; shift ;;
        --help) usage ;;
        *) echo "Unknown: $1"; usage ;;
    esac
done

check_system() {
    log "INFO" "Checking system state"
    local issues=0

    command -v kubectl >/dev/null 2>&1 && { echo "WARNING: kubectl exists"; ((issues++)); }
    systemctl is-active --quiet kubelet 2>/dev/null && { echo "WARNING: kubelet running"; ((issues++)); }
    systemctl is-active --quiet crio 2>/dev/null && { echo "WARNING: crio running"; ((issues++)); }
    systemctl is-active --quiet containerd 2>/dev/null && { echo "WARNING: containerd running"; ((issues++)); }
    [ -f /etc/kubernetes/admin.conf ] && { echo "WARNING: K8s config exists"; ((issues++)); }

    if [ $issues -gt 0 ]; then
        echo "$issues components detected. Use --rollback first."
        read -p "Continue? (y/N): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
}

rollback() {
    log "INFO" "Rolling back Kubernetes"

    # Stop services first
    systemctl stop kubelet 2>/dev/null || true
    systemctl stop crio containerd 2>/dev/null || true

    # Remove static pod manifests - critical step
    rm -rf /etc/kubernetes/manifests/* 2>/dev/null || true

    # Kill all Kubernetes processes by name
    for proc in kube-apiserver kube-controller-manager kube-scheduler kube-proxy etcd; do
        pkill -9 $proc 2>/dev/null || true
    done

    # Wait for pods to terminate
    sleep 3

    # Verify port 6443 is free, force kill if needed
    if netstat -tuln | grep -q ':6443'; then
        fuser -k 6443/tcp 2>/dev/null || true
        sleep 1
    fi

    # Force stop all containers
    if command -v crictl >/dev/null 2>&1; then
        log "INFO" "Cleaning CRI-O containers"
        for pod in $(crictl pods -q 2>/dev/null); do
            crictl stopp "$pod" 2>/dev/null || true
            crictl rmp "$pod" 2>/dev/null || true
        done
        for container in $(crictl ps -aq 2>/dev/null); do
            crictl stop "$container" 2>/dev/null || true
            crictl rm "$container" 2>/dev/null || true
        done
    fi

    # Force cleanup of containers and pods
    if command -v crictl >/dev/null 2>&1; then
        crictl --runtime-endpoint=unix:///var/run/crio/crio.sock stopp $(crictl pods -q) 2>/dev/null || true
        crictl --runtime-endpoint=unix:///var/run/crio/crio.sock rmp $(crictl pods -q) 2>/dev/null || true
    fi

    # Clean network namespaces - THIS IS THE KEY FIX
    if [ -d /var/run/netns ]; then
        for ns in /var/run/netns/*; do
            [ -e "$ns" ] && umount "$ns" 2>/dev/null || true
            [ -e "$ns" ] && rm -f "$ns" 2>/dev/null || true
        done
    fi

    # Now reset kubeadm
    kubeadm reset -f 2>/dev/null || true

    systemctl disable kubelet crio containerd 2>/dev/null || true

    dnf remove -y kubelet kubeadm kubectl cri-o cri-tools containerd.io 2>/dev/null || true

    rm -rf /etc/{kubernetes,crio,containerd,cni} \
           /var/lib/{kubelet,crio,containerd,cni} \
           /var/run/netns \
           $HOME/.kube /usr/local/bin/cilium \
           /etc/{sysctl,modules-load}.d/k8s.conf \
           /etc/yum.repos.d/{kubernetes,cri-o,devel:kubic*,docker-ce}.repo

    [ -f /etc/selinux/config.bak ] && mv /etc/selinux/config.bak /etc/selinux/config
    sed -i 's/^SELINUX=permissive$/SELINUX=enforcing/' /etc/selinux/config 2>/dev/null || true

    systemctl enable --now firewalld 2>/dev/null || true
    sed -i '/swap/ s/^#//' /etc/fstab 2>/dev/null && swapon -a 2>/dev/null || true

    iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X 2>/dev/null || true

    log "INFO" "Rollback complete. Reboot recommended."
    exit 0
}

setup_repos() {
    log "INFO" "Configuring repositories"

    if [ "$RUNTIME" = "crio" ]; then
        cat > /etc/yum.repos.d/cri-o.repo << EOF
[cri-o]
name=CRI-O
baseurl=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v${CRIO_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v${CRIO_VERSION}/rpm/repodata/repomd.xml.key
EOF
    else
        dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    fi

    cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
}

load_kernel_modules() {
    log "INFO" "Loading kernel modules"

    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
sctp
EOF

    # Load modules with error checking
    for module in overlay br_netfilter sctp; do
        if ! lsmod | grep -q "^$module"; then
            if ! modprobe $module 2>/dev/null; then
                log "WARN" "Failed to load $module - may be built-in or unavailable"
            else
                log "INFO" "Loaded $module module"
            fi
        else
            log "INFO" "$module already loaded"
        fi
    done
}

configure_sysctl() {
    log "INFO" "Configuring sysctl"

    cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.sctp.sctp_mem = 94500000 915000000 927000000
net.sctp.sctp_rmem = 4096 65536 16777216
net.sctp.sctp_wmem = 4096 65536 16777216
EOF

    if ! sysctl --system 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR" "sysctl configuration failed"
        exit 1
    fi
}

install_prometheus() {
    log "INFO" "Installing Prometheus stack"

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

    kubectl create namespace monitoring 2>/dev/null || true

    helm install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --set prometheus.prometheusSpec.retention=15d \
        --set prometheus.prometheusSpec.resources.requests.memory=2Gi \
        --set grafana.adminPassword=admin
        #--wait --timeout=10m

    log "INFO" "Prometheus installed - Grafana: http://$(kubectl get nodes -o wide | awk 'NR==2{print $6}'):$(kubectl get svc -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}')"
}

install_helm() {
    log "INFO" "Installing Helm"

    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    if command -v helm >/dev/null 2>&1; then
        log "INFO" "Helm installed: $(helm version --short)"
    else
        log "ERROR" "Helm installation failed"
        exit 1
    fi
}

install_runtime() {
    log "INFO" "Installing $RUNTIME"

    if [ "$RUNTIME" = "crio" ]; then
        dnf install -y cri-o cri-tools --disableexcludes=kubernetes

        mkdir -p /etc/crio/crio.conf.d
        cat > /etc/crio/crio.conf.d/02-cgroup.conf << EOF
[crio.runtime]
conmon_cgroup = "pod"
cgroup_manager = "systemd"
EOF
        systemctl enable --now crio
        echo 'KUBELET_EXTRA_ARGS="--container-runtime-endpoint=unix:///var/run/crio/crio.sock"' > /etc/sysconfig/kubelet
        CRI_SOCKET="unix:///var/run/crio/crio.sock"
    else
        dnf install -y containerd.io

        mkdir -p /etc/containerd
        containerd config default > /etc/containerd/config.toml
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
        systemctl enable --now containerd
        CRI_SOCKET="unix:///var/run/containerd/containerd.sock"
    fi

    log "INFO" "$RUNTIME installation complete"
}

install() {
    log "INFO" "Starting Kubernetes installation"
    echo "Runtime: $RUNTIME | Pod: $POD_NETWORK | Service: $SERVICE_NETWORK | Single-node: $SINGLE_NODE"

    # System prep
    log "INFO" "Preparing system"
    dnf update -y && dnf install -y wget curl vim git

    swapoff -a && sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    systemctl disable --now firewalld

    cp /etc/selinux/config /etc/selinux/config.bak 2>/dev/null || true
    setenforce 0 && sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

    setup_repos
    install_runtime
    load_kernel_modules
    configure_sysctl

    # Install Kubernetes
    log "INFO" "Installing Kubernetes components"
    dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
    systemctl enable kubelet

    # Wait for container runtime to be fully ready
    log "INFO" "Verifying container runtime status"
    sleep 5
    systemctl is-active --quiet ${RUNTIME} || {
        log "ERROR" "$RUNTIME is not running"
        exit 1
    }

    # Verify CRI socket is accessible
    if [ "$RUNTIME" = "crio" ]; then
        timeout 10 crictl --runtime-endpoint=unix:///var/run/crio/crio.sock info >/dev/null 2>&1 || {
            log "ERROR" "CRI-O socket not responding"
            systemctl status crio
            exit 1
        }
    fi
    log "INFO" "Configuring hostname resolution"
    HOSTNAME=$(hostname)
    HOSTIP=$API_ADDRESS
    if ! grep -q "$HOSTNAME" /etc/hosts; then
        echo "$HOSTIP $HOSTNAME" >> /etc/hosts
        log "INFO" "Added $HOSTNAME to /etc/hosts"
    fi


    log "INFO" "Pre-pulling Kubernetes images"
    kubeadm config images pull --cri-socket=$CRI_SOCKET 2>&1 | tee -a "$LOG_FILE"

    # Initialize cluster
    INIT_CMD="kubeadm init \
        --pod-network-cidr=$POD_NETWORK \
        --service-cidr=$SERVICE_NETWORK \
        --cri-socket=$CRI_SOCKET \
        --ignore-preflight-errors=NumCPU,Mem"
    [ -n "$API_ADDRESS" ] && INIT_CMD="$INIT_CMD --apiserver-advertise-address=$API_ADDRESS"

    log "INFO" "Initializing cluster"

    if ! eval $INIT_CMD 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR" "kubeadm init failed with exit code $?"
        exit 1
    fi

    mkdir -p $HOME/.kube || true
    cp /etc/kubernetes/admin.conf $HOME/.kube/config

    # Add PodNodeSelector and wait for restart
    log "INFO" "Enabling PodNodeSelector admission plugin"
    sudo sed -i 's/--enable-admission-plugins=NodeRestriction/--enable-admission-plugins=NodeRestriction,PodNodeSelector/' /etc/kubernetes/manifests/kube-apiserver.yaml
    sleep 45

    # Install Helm
    install_helm

    # Install SRIOV Plumbing
    helm install -n sriov-network-operator \
        --create-namespace --version 1.6.0 \
        --set sriovOperatorConfig.deploy=true \
        --set configDaemonNodeSelector='feature.node.kubernetes.io/network-sriov.capable: "true"' \
        --set sriovOperatorConfig.configurationMode=daemon \
        --set sriovOperatorConfig.enableInjector=false \
        --set sriovOperatorConfig.enableOperatorWebhook=false \
        sriov-network-operator oci://ghcr.io/k8snetworkplumbingwg/sriov-network-operator-chart

    # Single-node configuration
    if [ "$SINGLE_NODE" = "true" ]; then
        kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
        log "INFO" "Configured as single-node cluster"
    fi

    # Install Prometheus
    install_prometheus

    # Install CNI
    log "INFO" "Installing Cilium CNI"
    curl -sL https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz | tar -xz
    mv cilium /usr/local/bin/

    if [ -f /tmp/cilium-values.yaml ]; then
        cilium install --helm-values /tmp/cilium-values.yaml
    else
        cilium install --set sctp.enabled=true
    fi

    cilium status --wait


    log "INFO" "Installing OpenEBS"
    kubectl apply -f https://openebs.github.io/charts/openebs-operator.yaml
    kubectl wait --for=condition=ready pod -l app=openebs -n openebs --timeout=300s || log "WARN" "OpenEBS readiness check timed out"
    kubectl patch storageclass openebs-hostpath -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true

    # Install PTP
    kubectl apply -f https://raw.githubusercontent.com/bmw-ece-ntust/nino-c-ran-installation/refs/heads/main/charts/ptp-agent/daemonset.yaml
    kubectl apply -f https://raw.githubusercontent.com/bmw-ece-ntust/nino-c-ran-installation/refs/heads/main/charts/ptp-agent/configmap.yaml

    # Install Node Feature Discovery
    kubectl apply -k https://github.com/kubernetes-sigs/node-feature-discovery/deployment/overlays/default

    log "INFO" "Installing Multus CNI"
    kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
    kubectl wait --for=condition=ready pod -l app=multus -n kube-system --timeout=300s || log "WARN" "Multus readiness check timed out"

    log "INFO" "[!]-[ Installation complete ]"
    echo ""
    kubectl get nodes
    echo ""
    kubectl get pods -A
}

# Execute
[ "$ROLLBACK" = "true" ] && rollback
check_system
install
