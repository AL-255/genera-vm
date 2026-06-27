# Running Symbolics Open Genera 2.0 on a modern Linux desktop

Scripts to run the Open Genera Virtual Lisp Machine (VLM) with its GUI on a
current Linux machine (Wayland/GNOME, recent kernel and X.Org). Two approaches:

| Approach | Script | NFS (Genera file access) | When to use |
|----------|--------|--------------------------|-------------|
| **Host‑direct** | `run-genera-gui.sh` | needs host NFS (NFSv2 **unavailable** on kernels ≥ 6.x) | quick GUI, no file server needed |
| **VM + VNC** (recommended) | `run-genera-vm-vnc.sh` | **NFSv2 works** (served from inside the VM) | full setup incl. Genera's filesystem |

## Why a VM?

Genera is from the 1990s and hits two walls on modern systems:

1. **NFSv2.** Genera's NFS client speaks **NFSv2 over UDP**. Modern Linux kernels
   removed the NFSv2 *server* (`CONFIG_NFSD_V2` is gone), so the host cannot
   serve it. The VM runs Debian 11 (kernel 5.10) which still has NFSv2.
2. **The X server is too new.** Genera's old Xlib code misbehaves on X.Org 24.x.
   The VM runs an **older X server** (Xvnc / X.Org 1.20) and you view it over VNC.

There is also a VLM bug worked around by `genera-displayfix.so` (an `LD_PRELOAD`
shim): Genera mangles `$DISPLAY` (drops the colon, e.g. opens `"1"` instead of
`":1"`), which the shim repairs.

---

## 1. Dependencies (host)

Debian/Ubuntu package names:

```bash
# VM + VNC approach (recommended):
sudo apt install virtualbox qemu-utils xorriso wget openssh-client \
                 tigervnc-viewer            # or use the preinstalled "remmina"

# Host-direct approach also needs:
sudo apt install xserver-xephyr x11-xserver-utils x11-utils gcc libx11-dev \
                 nfs-kernel-server
```

(`qemu-utils` provides `qemu-img`; `tigervnc-viewer` provides `xtigervncviewer`.
If you have neither viewer, the script falls back to `remmina`.)

VirtualBox must be able to run a 64‑bit guest (VT‑x/AMD‑V enabled in BIOS).

## 2. Proprietary assets you must supply

These are **not** in the repo (Symbolics‑copyrighted, large). Place them in the
repo root before building:

| File | What it is |
|------|------------|
| `genera` | the VLM executable (Linux x86‑64) |
| `Genera-8-5-xlib-patched.vlod` | the Genera 8.5 world (xlib‑patched build) |
| `var_lib_symbolics.tar.gz` | the Genera filesystem (extracts to `/var/lib/symbolics`) |
| `VLM_debugger` | the VLM debugger blob referenced by `.VLM` |

They are commonly distributed via the Open Genera archives (e.g.
`archives.loomcom.com`). This repo does not provide them.

---

## 3. VM + VNC approach (recommended)

### Build the VM once

```bash
cd vm
./build-vm.sh
```

This downloads a Debian 11 cloud image, builds a cloud‑init seed, creates a
VirtualBox VM (`genera-nfs`, ssh on `127.0.0.1:2222`), then copies the assets in
and provisions NFSv2 + tap0 + a time server + the display shim. VM login is
`genera` / (set your own with `vmssh 'echo genera:genera | sudo chpasswd'`).

### Run Genera

```bash
./run-genera-vm-vnc.sh                 # auto-sizes to the DVI-I-1 monitor (1:1)
./run-genera-vm-vnc.sh 1600x1200       # or force a size
MONITOR=HDMI-1 ./run-genera-vm-vnc.sh  # target a different monitor
```

It starts Xvnc + Genera inside the VM, tunnels VNC (`localhost:5901`) and opens
a viewer. The session is **durable** — re‑running just reconnects; it doesn't
kill a running Genera. Click the viewer and at `Command:` type e.g. `Login user`.

## 4. Host‑direct approach (no VM)

```bash
cp .VLM.example .VLM        # then edit worldSearchPath to this directory
sudo ./genera-tap0.sh "$USER"   # create the tap0 interface (or install the service below)
./run-genera-gui.sh         # Xephyr, borderless on the detected monitor
```

`run-genera-gui.sh` auto‑detects the `DVI-I-1` monitor, runs a nested **Xephyr**
sized to it (no scaling → pixel‑perfect), repairs the `$DISPLAY` bug via the
shim, and places the window borderless on that monitor. Note: Genera file access
over NFS will **not** work here on a kernel without NFSv2 — use the VM approach
for that.

### Make `tap0` persistent across reboots

```bash
sudo cp genera-tap0.service /etc/systemd/system/
sudo systemctl enable --now genera-tap0.service
```

---

## File overview

```
run-genera-vm-vnc.sh     host: VM + Xvnc(old X) + VNC viewer   ← recommended
run-genera-vm-x.sh       host: VM + ssh-X-forward into Xephyr
run-genera-gui.sh        host: run the VLM directly in a Xephyr window
genera-displayfix.c      LD_PRELOAD shim fixing Genera's $DISPLAY parsing bug
genera-fullscreen.c      makes the Xephyr window borderless on a monitor
genera-tap0.sh|.service  create the tap0 net interface Genera needs
genera-nfs.sh            ensure host NFS is up (host-direct only; no NFSv2 on new kernels)
.VLM.example             template VLM config for the host-direct approach
vm/
  build-vm.sh            one-shot: create + provision the Debian VM
  vmssh, vmscp           ssh/scp wrappers to the VM
  seed/                  cloud-init (user-data.template, meta-data)
  guest/                 scripts deployed INTO the VM:
    provision.sh           one-time VM setup (NFSv2, exports, time, shim, .VLM)
    vm-prep.sh             idempotent prereqs (tap0, NFSv2, NAT, time)
    run-vm-vnc.sh          start Xvnc + Genera (for the VNC approach)
    run-vm-genera.sh       start Genera for the ssh-X-forward approach
    genera-displayfix.c    the shim (built in the VM)
```

## Notes / gotchas

- **VirtualBox 64‑bit guest** needs `--ioapic on --pae on` or systemd panics
  (`Attempted to kill init`); `build-vm.sh` sets these.
- **NFSv2 on Debian 11** must be forced on `rpc.nfsd` (`-V 2 -V 3 -N 4`); the
  `nfs.conf` `vers2=y` key is ignored. Beware `rpc.nfsd -U` means *disable* UDP.
- **Time:** the VM runs an RFC868 time server + NAT so Genera gets the date over
  the network and doesn't stop at the cold‑load "type the date" prompt.
- **Monitor name** can change between reboots/replugs (`DVI-I-1` vs `DVI-I-2`,
  position too). The scripts resolve it live via `xrandr`; set `MONITOR=` to override.
- **Integer/nearest‑neighbor scaling** isn't wired in (Xephyr rejects RandR
  transforms). With VNC, scale in the viewer; `gamescope -F nearest -S integer`
  is a possible route if you have a working GPU/Vulkan.

## References

- Symbolics documentation & software archive — <https://www.bitsavers.org/pdf/symbolics/>
- Open Genera on Linux notes (oubiwann) — <https://gist.github.com/oubiwann/1e7aadfc22e3ae908921aeaccf27e82d>
- Running Open Genera 2.0 on Linux (loomcom) — <https://archives.loomcom.com/genera/genera-install.html>
