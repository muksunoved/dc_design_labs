#!/bin/bash
sleep 2
ip addr add 10.3.3.1/31 dev eth1 2>/dev/null || true
ip link set eth1 up
ip route add default via 10.3.3.0 2>/dev/null || true
while true; do sleep 60; done
