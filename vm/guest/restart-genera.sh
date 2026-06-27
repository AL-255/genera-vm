#!/usr/bin/env bash
# Restart the X server (Xvnc) AND the Genera VLM inside the VM. Run in the VM.
set -u
GEO=$(pgrep -ax Xvnc 2>/dev/null | grep -o 'geometry [0-9]*x[0-9]*' | awk '{print $2}')
GEO=${GEO:-1280x1024}
echo "Killing genera + Xvnc..."
pkill -x genera 2>/dev/null || true
pkill -x Xvnc 2>/dev/null || true
pkill -f "sleep infinity > /tmp/genera_in" 2>/dev/null || true
sleep 2
echo "Starting fresh Xvnc + genera ($GEO)..."
GENERA_GEOMETRY="$GEO" bash /home/genera/genera/run-vm-vnc.sh
