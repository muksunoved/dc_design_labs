#!/bin/bash
# Host1 startup configuration — applied by netlab files plugin
# eth1 connects to leaf1

# Wait for interface to be available
sleep 2

# Assign IP on the link to leaf1
ip addr add 10.3.1.1/31 dev eth1 2>/dev/null || true
ip link set eth1 up

# Default route via leaf1
ip route add default via 10.3.1.0 2>/dev/null || true

# Loop to keep container alive
while true; do sleep 60; done
