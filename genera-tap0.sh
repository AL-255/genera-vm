#!/usr/bin/env bash
# Create the tap0 interface Open Genera needs, owned by the genera user so the
# (unprivileged) VLM can attach to it. Idempotent: safe to run repeatedly.
# Must run as root (uses ip tuntap / ip addr).
set -e

GENERA_USER="${1:-yukidama}"
HOST_IP=192.168.2.1
PREFIX=24

if ! ip link show tap0 >/dev/null 2>&1; then
  ip tuntap add dev tap0 mode tap user "$GENERA_USER"
fi
# (re)assign the host-side address if missing
if ! ip -4 addr show tap0 | grep -q "$HOST_IP/"; then
  ip addr add "$HOST_IP/$PREFIX" dev tap0
fi
ip link set tap0 up
echo "tap0 ready: $(ip -4 addr show tap0 | grep -o 'inet [^ ]*')"
