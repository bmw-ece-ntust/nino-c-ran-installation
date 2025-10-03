#!/bin/bash
set -e

HOSTNAME=$(hostname)
CONFIG_FILE="/config/${HOSTNAME}"

if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="/config/default"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: No config found for hostname $HOSTNAME"
    exit 1
fi

source "$CONFIG_FILE"

if [ "$interface" = "auto" ]; then
    interface=$(ip -o link show | awk -F': ' '$2 !~ /^(lo|docker|cni|veth|br-|cilium)/ && $2 !~ /^bond/ {print $2; exit}')
    if [ -z "$interface" ]; then
        echo "ERROR: No suitable PTP interface found"
        exit 1
    fi
    echo "Auto-detected interface: $interface"
fi

if ! ip link show "$interface" &>/dev/null; then
    echo "ERROR: Interface $interface does not exist"
    exit 1
fi

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

echo "Node: $HOSTNAME | Interface: $interface | Config: $CONFIG_FILE"

export INTERFACE="$interface"
export PTP_CONFIG="/tmp/ptp4l.conf"
