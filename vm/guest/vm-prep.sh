#!/usr/bin/env bash
# Idempotent VM-side prerequisites for the Genera VLM. Run as root.
set -u
# tap0 (host side of Genera net)
if ! ip link show tap0 >/dev/null 2>&1; then
  ip tuntap add dev tap0 mode tap user genera
  ip addr add 192.168.2.1/24 dev tap0
fi
ip link set tap0 up
# NFSv2/v3 server (versions forced by the systemd drop-in) + export
systemctl is-active --quiet nfs-server || systemctl start nfs-server
exportfs -ra
# Internet for the Genera net + RFC868 time on the gateway
sysctl -wq net.ipv4.ip_forward=1
UP=$(ip route show default | awk "{print \$5; exit}")
iptables -t nat -C POSTROUTING -s 192.168.2.0/24 -o "$UP" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s 192.168.2.0/24 -o "$UP" -j MASQUERADE
iptables -C FORWARD -i tap0 -o "$UP" -j ACCEPT 2>/dev/null || iptables -A FORWARD -i tap0 -o "$UP" -j ACCEPT
iptables -C FORWARD -i "$UP" -o tap0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i "$UP" -o tap0 -m state --state RELATED,ESTABLISHED -j ACCEPT
systemctl is-active --quiet openbsd-inetd || systemctl restart openbsd-inetd 2>/dev/null || true
echo "vm-prep ok: tap0=$(ip -4 addr show tap0|grep -o "192.168.2.1"), nfs v2=$(grep -o +2 /proc/fs/nfsd/versions 2>/dev/null)"
