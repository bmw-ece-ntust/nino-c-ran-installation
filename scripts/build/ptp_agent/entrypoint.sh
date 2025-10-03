#!/bin/bash
set -e

HOSTNAME=$(hostname)
CONFIG_FILE="/config/config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found at $CONFIG_FILE"
    exit 1
fi

# Function to read YAML value
read_yaml() {
    local node=$1
    local key=$2
    grep -A 20 "^${node}:" "$CONFIG_FILE" | grep "^  ${key}:" | awk '{print $2}' | head -1
}

# Try to read node-specific config, fallback to default
interface=$(read_yaml "$HOSTNAME" "interface")
if [ -z "$interface" ]; then
    echo "No config for $HOSTNAME, using default"
    interface=$(read_yaml "default" "interface")
    domain=$(read_yaml "default" "domain")
    slave_only=$(read_yaml "default" "slave_only")
    tx_timeout=$(read_yaml "default" "tx_timeout")
    log_level=$(read_yaml "default" "log_level")
    network_transport=$(read_yaml "default" "network_transport")
    hybrid_e2e=$(read_yaml "default" "hybrid_e2e")
else
    domain=$(read_yaml "$HOSTNAME" "domain")
    slave_only=$(read_yaml "$HOSTNAME" "slave_only")
    tx_timeout=$(read_yaml "$HOSTNAME" "tx_timeout")
    log_level=$(read_yaml "$HOSTNAME" "log_level")
    network_transport=$(read_yaml "$HOSTNAME" "network_transport")
    hybrid_e2e=$(read_yaml "$HOSTNAME" "hybrid_e2e")
fi

# Auto-detect interface if needed
if [ "$interface" = "auto" ]; then
    interface=$(ip -o link show | awk -F': ' '$2 !~ /^(lo|docker|cni|veth|br-|cilium)/ && $2 !~ /^bond/ {print $2; exit}')
    if [ -z "$interface" ]; then
        echo "ERROR: No suitable PTP interface found"
        exit 1
    fi
    echo "Auto-detected interface: $interface"
fi

# Verify interface exists
if ! ip link show "$interface" &>/dev/null; then
    echo "ERROR: Interface $interface does not exist"
    exit 1
fi

# Generate ptp4l.conf
cat > /tmp/ptp4l.conf <<EOF
[global]
domainNumber            ${domain}
slaveOnly               ${slave_only}
time_stamping           hardware
tx_timestamp_timeout    ${tx_timeout}
logging_level           ${log_level}
summary_interval        0
[${interface}]
network_transport       ${network_transport}
hybrid_e2e              ${hybrid_e2e}
EOF

echo "Node: $HOSTNAME | Interface: $interface"
cat /tmp/ptp4l.conf

export INTERFACE="$interface"
export PTP_CONFIG="/tmp/ptp4l.conf"
