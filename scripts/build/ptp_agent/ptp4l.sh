#!/bin/bash
set -e

source /entrypoint-base.sh

echo "Starting ptp4l on $INTERFACE"
exec ptp4l -i "$INTERFACE" -m -H -2 -s -f "$PTP_CONFIG"
