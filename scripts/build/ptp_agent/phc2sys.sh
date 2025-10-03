#!/bin/bash
set -e

# Wait for ptp4l to initialize
sleep 10

source /entrypoint.sh

echo "Starting phc2sys on $INTERFACE"
exec phc2sys -w -m -s "$INTERFACE" -R 8 -f "$PTP_CONFIG"
