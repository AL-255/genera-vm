#!/usr/bin/env bash
# Launch Symbolics Genera (Open Genera VLM) with its GUI visible.
#
# Two problems are worked around here:
#  1. Wayland: the VLM's old Xlib code won't map windows on XWayland, so we
#     run it inside a dedicated nested Xephyr X server (with -ac).
#  2. A bug in this VLM build: its $DISPLAY parser strips the colon and hands
#     XOpenDisplay a bare number ("3" instead of ":3"), which always fails, so
#     no window ever opens ("Waiting for X server..." forever). The LD_PRELOAD
#     shim genera-displayfix.so rewrites a bare-number display name back to
#     ":<n>" so the connection succeeds.
set -u

GENERA_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
NESTED_DISPLAY=:3
MONITOR=DVI-I-1           # host monitor to cover (override: MONITOR=HDMI-1 ./run-genera-gui.sh)
SHIM="$GENERA_DIR/genera-displayfix.so"

cd "$GENERA_DIR" || exit 1

# Resolve the target monitor's LIVE geometry from the host X server (:0); the
# layout can change between reboots/replugs, so never hardcode it. xrandr prints
# e.g.  " 1: +DVI-I-2 2048/420x1536/320+2560+0  DVI-I-2" -> strip the /mm parts.
read_monitor() {
  DISPLAY=:0 xrandr --listmonitors 2>/dev/null | awk -v m="$1" \
    '$NF==m { g=$3; gsub(/\/[0-9]+/,"",g); print g }'   # -> WxH+X+Y
}
GEOM=$(read_monitor "$MONITOR")
if [ -z "$GEOM" ]; then
  echo "WARNING: monitor '$MONITOR' not found; falling back to primary." >&2
  MONITOR=$(DISPLAY=:0 xrandr --listmonitors 2>/dev/null | awk '/\*/{print $NF; exit}')
  GEOM=$(read_monitor "$MONITOR")
fi
[ -n "$GEOM" ] || { echo "ERROR: could not read any monitor geometry from :0" >&2; exit 1; }
SCREEN=${GEOM%%+*}          # WxH
_rest=${GEOM#*+}            # X+Y
MON_X=${_rest%+*}
MON_Y=${_rest#*+}
echo "Target monitor $MONITOR: $SCREEN at +$MON_X+$MON_Y"

# 0. The VLM needs the tap0 network interface; without it the VLM faults into
#    its debugger (TUNSETIFF: Operation not permitted). tap0 is not persistent
#    across reboots, so recreate it if missing (needs sudo, once per boot).
if ! ip link show tap0 >/dev/null 2>&1; then
  echo "tap0 is missing - creating it (needs sudo)..."
  sudo "$GENERA_DIR/genera-tap0.sh" "$USER" || {
    echo "ERROR: could not create tap0. Run: sudo $GENERA_DIR/genera-tap0.sh $USER" >&2
    exit 1
  }
fi

# 0b. The Genera world mounts the host filesystem over NFS; make sure the NFS
#     server is up (start it if a boot race / transient failure left it down).
if ! systemctl is-active --quiet nfs-server; then
  echo "NFS server is not running - starting it (needs sudo)..."
  sudo "$GENERA_DIR/genera-nfs.sh" || {
    echo "ERROR: could not start NFS. Run: sudo $GENERA_DIR/genera-nfs.sh" >&2
    exit 1
  }
fi

# Build the display-fix shim if missing.
if [ ! -f "$SHIM" ]; then
  echo "Building display-fix shim..."
  gcc -shared -fPIC -o "$SHIM" "$GENERA_DIR/genera-displayfix.c" -ldl || exit 1
fi

# 1. Start Xephyr if it isn't already up on $NESTED_DISPLAY.
if ! DISPLAY=$NESTED_DISPLAY xdpyinfo >/dev/null 2>&1; then
  echo "Starting Xephyr on $NESTED_DISPLAY ($SCREEN)..."
  # No -resizeable: resizing makes Xephyr scale the framebuffer (blurry).
  # Fixed screen size keeps Genera pixel-perfect (1 px = 1 screen px).
  setsid Xephyr -br -ac -noreset -screen "$SCREEN" "$NESTED_DISPLAY" \
      >/tmp/xephyr.log 2>&1 &
  for _ in $(seq 1 40); do
    DISPLAY=$NESTED_DISPLAY xdpyinfo >/dev/null 2>&1 && break
    sleep 0.25
  done
fi
if ! DISPLAY=$NESTED_DISPLAY xdpyinfo >/dev/null 2>&1; then
  echo "ERROR: Xephyr did not come up. See /tmp/xephyr.log" >&2
  exit 1
fi
echo "Xephyr ready on $NESTED_DISPLAY"

# 2. Keep a writer on a FIFO so the cold-load console never sees EOF
#    (otherwise it prompts to exit and dies when run detached).
FIFO=/tmp/genera_in
rm -f "$FIFO"; mkfifo "$FIFO"
setsid bash -c "exec sleep infinity > $FIFO" >/dev/null 2>&1 &

# 3. Make the Xephyr window borderless and move it to cover the target monitor.
"$GENERA_DIR/genera-fullscreen" "$MON_X" "$MON_Y" &

# 4. Launch the VLM into the nested display with the display-fix shim.
#    -geometry makes the Genera console match the resolved monitor size.
echo "Launching genera (DISPLAY=$NESTED_DISPLAY)..."
setsid bash -c "exec env DISPLAY='$NESTED_DISPLAY' LD_PRELOAD='$SHIM' ./genera -geometry ${SCREEN}+0+0 < $FIFO" \
    >/tmp/genera_run.log 2>&1 &

echo "genera launched (borderless, covering $MONITOR). Boot log: /tmp/genera_run.log"
