#!/usr/bin/env bash
# Restart the Genera VLM running inside the VM: kill the current X server (Xvnc)
# and genera, then start both fresh. A connected VNC viewer will drop; reconnect
# with run-genera-vm-vnc.sh.
set -u

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VMDIR=$DIR/vm
VM=genera-nfs

if ! VBoxManage list runningvms | grep -q "\"$VM\""; then
  echo "VM '$VM' is not running. Start it first:  $DIR/run-genera-vm-vnc.sh" >&2
  exit 1
fi

echo "Restarting Xvnc + Genera in '$VM'..."
"$VMDIR/vmssh" 'bash /home/genera/genera/restart-genera.sh'
echo "Done. Reconnect your viewer with: $DIR/run-genera-vm-vnc.sh"
