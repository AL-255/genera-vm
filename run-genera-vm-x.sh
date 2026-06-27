#!/usr/bin/env bash
# Run the Genera VLM inside the Debian VM (which serves NFSv2 for Genera) and
# forward its X windows into a host-side Xephyr window, borderless/fullscreen on
# a chosen monitor (same display behaviour as run-genera-gui.sh).
#
# Flow: host Xephyr (:3)  <--ssh X11 tunnel--  genera (in VM, DISPLAY=localhost:10.0)
set -u

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VMDIR=$DIR/vm
VM=genera-nfs
NESTED=:3
MONITOR=DVI-I-1          # host monitor to cover (override: MONITOR=HDMI-1 ./run-genera-vm.sh)

# Resolve the target monitor's LIVE geometry from the host X server (:0); the
# layout can change between reboots/replugs, so never hardcode it.
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
SCREEN=${GEOM%%+*}; _rest=${GEOM#*+}; MON_X=${_rest%+*}; MON_Y=${_rest#*+}
echo "Target monitor $MONITOR: $SCREEN at +$MON_X+$MON_Y"

# 0. Kill any previous instance (host ssh X-forwarder + VM-side genera).
pkill -f 'ssh .*run-vm-genera.sh' 2>/dev/null || true

# 1. The VM must exist and be running. Detect; if stopped, prompt to start it.
if ! VBoxManage list vms | grep -q "\"$VM\""; then
  echo "VM '$VM' does not exist. Build it first:  $DIR/vm/build-vm.sh" >&2
  exit 1
fi
if ! VBoxManage list runningvms | grep -q "\"$VM\""; then
  read -r -p "VM '$VM' is not running. Start it now? [Y/n] " ans
  case "${ans:-Y}" in
    [Nn]*) echo "Not started. Run:  VBoxManage startvm $VM --type headless"; exit 1 ;;
    *) echo "Starting VM $VM..."; VBoxManage startvm "$VM" --type headless >/dev/null ;;
  esac
fi
echo -n "Waiting for VM ssh"
for _ in $(seq 1 60); do "$VMDIR/vmssh" true >/dev/null 2>&1 && break; echo -n .; sleep 3; done; echo
"$VMDIR/vmssh" 'pkill -x genera 2>/dev/null; pkill -f "sleep infinity > /tmp/genera_in" 2>/dev/null; true' 2>/dev/null || true
sleep 1

# 2. VM-side prerequisites (tap0, NFSv2, time, NAT).
"$VMDIR/vmssh" 'sudo /home/genera/genera/vm-prep.sh' 2>/dev/null || true

# 3. Start the host Xephyr sized exactly to the monitor (no -resizeable -> no scaling).
if ! DISPLAY=$NESTED xdpyinfo >/dev/null 2>&1; then
  echo "Starting Xephyr on $NESTED ($SCREEN)..."
  setsid Xephyr -br -ac -noreset -screen "$SCREEN" "$NESTED" >/tmp/xephyr.log 2>&1 &
  for _ in $(seq 1 40); do DISPLAY=$NESTED xdpyinfo >/dev/null 2>&1 && break; sleep 0.25; done
fi
DISPLAY=$NESTED xdpyinfo >/dev/null 2>&1 || { echo "ERROR: Xephyr did not start" >&2; exit 1; }
echo "Xephyr ready on $NESTED"

# 4. Make the Xephyr window borderless and move it to cover the target monitor.
DISPLAY=:0 "$DIR/genera-fullscreen" "$MON_X" "$MON_Y" >/dev/null 2>&1 &

# 5. ssh -X into the VM (DISPLAY=Xephyr), run genera filling the screen (-geometry).
echo "Launching genera in VM -> Xephyr $NESTED (borderless on $MONITOR) ..."
exec env DISPLAY=$NESTED ssh -X -i "$VMDIR/id_genera" -p 2222 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ForwardX11Timeout=8h \
  genera@127.0.0.1 "env GENERA_GEOMETRY=$SCREEN bash ~/genera/run-vm-genera.sh"
