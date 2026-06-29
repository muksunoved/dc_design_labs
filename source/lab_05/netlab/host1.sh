#!/bin/bash
# Host1 startup configuration — applied by netlab files plugin
# eth1 connects to leaf1 (VLAN 10 access port — VXLAN overlay)
# Overlay: VLAN 10 / VNI 10010 / subnet 192.168.10.0/24

# Install networking tools (not present in minimal Ubuntu 22.04 image)
apt-get update -qq > /dev/null 2>&1
apt-get install -y -qq iproute2 iputils-ping > /dev/null 2>&1

# Wait for interface to be available
sleep 2

# Assign overlay IP on eth1 (VLAN 10 subnet)
ip addr add 192.168.10.11/24 dev eth1 2>/dev/null || true
ip link set eth1 up

# Loop to keep container alive
while true; do sleep 60; done
