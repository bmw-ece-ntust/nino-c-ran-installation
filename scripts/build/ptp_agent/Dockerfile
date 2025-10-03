FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    linuxptp \
    curl \
    vim \
    iproute2 \
    ethtool \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY ptp4l.sh /ptp4l.sh
COPY phc2sys.sh /phc2sys.sh

RUN chmod +x /entrypoint.sh /ptp4l.sh /phc2sys.sh
