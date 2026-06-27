#!/usr/bin/env bash
# One-time provisioning INSIDE the VM. Assumes the Genera assets and the guest
# scripts have already been copied to /home/genera/genera. Run as user `genera`
# (has passwordless sudo). Idempotent.
set -e
cd /home/genera/genera

# --- NFSv2/v3 server (Genera needs NFSv2/UDP; Debian 11's nfs-utils ignores
#     nfs.conf vers2, so force versions on rpc.nfsd via a systemd drop-in) ---
sudo mkdir -p /etc/systemd/system/nfs-server.service.d
printf '[Service]\nEnvironment=RPCNFSDARGS=-V 2 -V 3 -N 4 8\n' \
  | sudo tee /etc/systemd/system/nfs-server.service.d/v2.conf >/dev/null
printf '[nfsd]\nvers2=y\nvers3=y\nvers4=y\nudp=y\ntcp=y\n' | sudo tee /etc/nfs.conf >/dev/null

# --- Genera network names + export of the host filesystem ---
grep -q genera-vlm /etc/hosts || \
  printf '192.168.2.1\tgenera-vlm\n192.168.2.2\tgenera\n' | sudo tee -a /etc/hosts >/dev/null
printf '/\tgenera(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000,insecure)\n' \
  | sudo tee /etc/exports >/dev/null

# --- Internet for the Genera net + RFC868 time server (so Genera gets time) ---
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-genera.conf >/dev/null
grep -qE '^time' /etc/inetd.conf 2>/dev/null || \
  printf 'time\tstream\ttcp\tnowait\troot\tinternal\ntime\tdgram\tudp\twait\troot\tinternal\n' \
  | sudo tee -a /etc/inetd.conf >/dev/null

# --- Extract the Genera filesystem (what gets NFS-exported) ---
sudo tar xzf var_lib_symbolics.tar.gz -C /var/lib/
sudo chown -R genera:genera /var/lib/symbolics

# --- Build the display-fix shim; make binaries executable ---
cc -shared -fPIC -o genera-displayfix.so genera-displayfix.c -ldl
chmod +x genera *.sh

# --- VLM config ---
cat > .VLM <<VLMEOF
genera.network: tap0:INTERNET|192.168.2.2;gateway=192.168.2.1
genera.virtualMemory: 512
genera.trace: no
genera.worldSearchPath: /home/genera/genera
*main.geometry: 1280x1024+0+0
*coldLoad.geometry: 800x600+0+0
genera.world: Genera-8-5-xlib-patched.vlod
genera.spy: no
genera.debugger: VLM_debugger
VLMEOF

sudo systemctl daemon-reload
sudo systemctl enable --now rpcbind nfs-server openbsd-inetd 2>/dev/null || true
sudo /home/genera/genera/vm-prep.sh
echo "provision done: NFSv2 = $(grep -o +2 /proc/fs/nfsd/versions 2>/dev/null)"
