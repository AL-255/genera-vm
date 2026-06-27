#!/usr/bin/env bash
# Launch the Genera VLM in the VM, displaying via the inherited (ssh-forwarded) X
# DISPLAY. Foreground, to keep the X tunnel open. GENERA_GEOMETRY (WxH) sizes the
# console to fill the host Xephyr screen.
set -u
cd /home/genera/genera
if ! ip link show tap0 >/dev/null 2>&1; then
  sudo ip tuntap add dev tap0 mode tap user genera
  sudo ip addr add 192.168.2.1/24 dev tap0
  sudo ip link set tap0 up
fi
FIFO=/tmp/genera_in; rm -f "$FIFO"; mkfifo "$FIFO"
setsid bash -c "exec sleep infinity > $FIFO" >/dev/null 2>&1 &
GEO="${GENERA_GEOMETRY:-1280x1024}+0+0"
echo "Launching genera, GENERA_REAL_DISPLAY=$DISPLAY geometry=$GEO"
exec env GENERA_REAL_DISPLAY="$DISPLAY" \
     LD_PRELOAD=/home/genera/genera/genera-displayfix.so \
     ./genera -geometry "$GEO" < "$FIFO"
