#!/usr/bin/env bash
# Ensure the host NFS server is running so the Genera VLM can mount the host
# filesystem. The export is defined in /etc/exports:
#     /   genera(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
# where "genera" = 192.168.2.2 (the Lisp world, via tap0). Idempotent; run as root.
set -e

# rpcbind is required for NFSv2/v3 (which Genera uses).
if ! systemctl is-active --quiet rpcbind; then
  echo "starting rpcbind..."; systemctl start rpcbind
fi

if ! systemctl is-active --quiet nfs-server; then
  echo "starting nfs-server..."; systemctl start nfs-server
fi

# (Re)apply exports. Safe to run repeatedly; also fixes the case where nfsd came
# up before the network/hosts were ready and the export to "genera" didn't take.
exportfs -ra

echo "NFS server active. Current exports:"
exportfs -v
