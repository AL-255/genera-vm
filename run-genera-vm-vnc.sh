#!/usr/bin/env bash
# Run the Genera VLM in the Debian VM against an OLD X server (Xvnc) running
# INSIDE the VM, and view it from the host over VNC. This avoids the host's
# too-new X server (whose newer behaviour breaks Genera's old Xlib code).
#
#   genera --> Xvnc :1 (in VM, X.org ~1.20) --VNC 5901--> ssh tunnel --> host viewer
#
# Usage: ./run-genera-vm-vnc.sh [WIDTHxHEIGHT]
#   With no argument, the size auto-detects from the DVI-I-1 monitor (1:1).
set -u

DIR=/home/yukidama/genera
VMDIR=$DIR/vm
VM=genera-nfs
MONITOR=DVI-I-1          # host monitor whose size to match (override: MONITOR=HDMI-1 ...)
PORT=5901

# Size: explicit arg wins; otherwise auto-detect the monitor's live resolution.
if [ "${1:-}" ]; then
  GEO=$1
else
  GEO=$(DISPLAY=:0 xrandr --listmonitors 2>/dev/null | awk -v m="$MONITOR" \
        '$NF==m { g=$3; gsub(/\/[0-9]+/,"",g); sub(/\+.*/,"",g); print g }')   # WxH
  if [ -z "$GEO" ]; then
    GEO=$(DISPLAY=:0 xrandr --listmonitors 2>/dev/null | awk \
          '/\*/{ g=$3; gsub(/\/[0-9]+/,"",g); sub(/\+.*/,"",g); print g; exit }')  # primary
  fi
  GEO=${GEO:-1280x1024}
fi
echo "Display size: $GEO (monitor $MONITOR)"

# Note: unlike the X-forward script, the VNC session is durable — Xvnc + genera
# keep running in the VM regardless of the viewer. Re-running this script just
# reconnects; it does NOT kill a running genera (so you don't lose your session).

# 1. Make sure the VM is running.
if ! VBoxManage list runningvms | grep -q "\"$VM\""; then
  echo "Starting VM $VM..."; VBoxManage startvm "$VM" --type headless >/dev/null
fi
echo -n "Waiting for VM ssh"
for _ in $(seq 1 60); do "$VMDIR/vmssh" true >/dev/null 2>&1 && break; echo -n .; sleep 3; done; echo

# 2. Apply prerequisites (tap0, NFSv2, time, NAT). Idempotent.
"$VMDIR/vmssh" 'sudo /home/genera/genera/vm-prep.sh' 2>/dev/null || true
# Make sure the in-VM X server is installed.
"$VMDIR/vmssh" 'command -v Xvnc >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y tigervnc-standalone-server xfonts-base x11-utils' 2>/dev/null || true

# 3. Ensure Xvnc + genera are running in the VM (started only if not already up;
#    detached, so the session persists across viewer connects).
echo "Ensuring Xvnc + genera in VM ($GEO)..."
"$VMDIR/vmssh" "GENERA_GEOMETRY=$GEO VNC_PORT=$PORT bash /home/genera/genera/run-vm-vnc.sh" 2>/dev/null

# 4. Forward the VNC port from the VM to the host (re-establish if needed).
pkill -f "ssh .*${PORT}:localhost:${PORT}" 2>/dev/null || true
ssh -fNT -L "${PORT}:localhost:${PORT}" -i "$VMDIR/id_genera" -p 2222 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ExitOnForwardFailure=yes genera@127.0.0.1
echo "VNC tunnel up: host localhost:${PORT} -> VM :1"

# 5. Open a VNC viewer on the host.
echo "Connecting viewer..."
if command -v xtigervncviewer >/dev/null; then
  exec xtigervncviewer "localhost:${PORT}"
elif command -v gvncviewer >/dev/null; then
  exec gvncviewer "localhost:${PORT}"
else
  exec remmina -c "vnc://localhost:${PORT}"
fi
