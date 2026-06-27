#!/usr/bin/env bash
# Start an in-VM X server (Xvnc, older X.org) and run the Genera VLM on it.
# Reuses a running session unless the requested geometry changed.
set -u
cd /home/genera/genera
GEO="${GENERA_GEOMETRY:-1280x1024}"
PORT="${VNC_PORT:-5901}"
DISP=:1
RUNGEO=$(pgrep -ax Xvnc 2>/dev/null | grep -o "geometry [0-9]*x[0-9]*" | awk "{print \$2}")
if pgrep -x Xvnc >/dev/null && [ "$RUNGEO" != "$GEO" ]; then
  echo "geometry $RUNGEO -> $GEO; restarting Xvnc+genera"
  pkill -x genera 2>/dev/null; pkill -x Xvnc 2>/dev/null
  pkill -f "sleep infinity > /tmp/genera_in" 2>/dev/null; sleep 1
fi
if ! pgrep -x Xvnc >/dev/null; then
  setsid Xvnc "$DISP" -geometry "$GEO" -depth 24 -SecurityTypes None \
     -rfbport "$PORT" -AlwaysShared -desktop genera >/tmp/xvnc.log 2>&1 &
  for _ in $(seq 1 40); do [ -S /tmp/.X11-unix/X1 ] && break; sleep 0.25; done
fi
[ -S /tmp/.X11-unix/X1 ] || { echo "Xvnc failed; see /tmp/xvnc.log"; tail /tmp/xvnc.log; exit 1; }
if pgrep -x genera >/dev/null; then echo "genera already running ($GEO) - reusing."; exit 0; fi
FIFO=/tmp/genera_in; rm -f "$FIFO"; mkfifo "$FIFO"
setsid bash -c "exec sleep infinity > $FIFO" >/dev/null 2>&1 &
setsid env DISPLAY="$DISP" GENERA_REAL_DISPLAY="$DISP" \
   LD_PRELOAD=/home/genera/genera/genera-displayfix.so \
   ./genera -geometry "${GEO}+0+0" < "$FIFO" >/tmp/genera_run.log 2>&1 &
sleep 1
echo "Xvnc on $DISP (rfb $PORT), genera launched. geometry=$GEO"
