#!/usr/bin/env bash
# Build the Debian VM that runs the Genera VLM and serves NFSv2 for it.
# Reproduces the whole guest from scratch: cloud image + cloud-init + provision.
#
# Prereqs on the HOST: VirtualBox, qemu-img, xorriso, wget, ssh/scp, ssh-keygen.
# You must place the proprietary Genera assets in the repo root first (see README):
#   genera  Genera-8-5-xlib-patched.vlod  var_lib_symbolics.tar.gz  VLM_debugger
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)     # .../vm
ROOT=$(dirname "$HERE")                  # repo root
VM=genera-nfs
KEY=$HERE/id_genera
IMG_URL=https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2
ASSETS=(genera Genera-8-5-xlib-patched.vlod var_lib_symbolics.tar.gz VLM_debugger)

echo "== checking host tools =="
for t in VBoxManage qemu-img xorriso wget ssh scp ssh-keygen; do
  command -v "$t" >/dev/null || { echo "ERROR: missing host tool: $t"; exit 1; }
done
echo "== checking Genera assets =="
for a in "${ASSETS[@]}"; do
  [ -f "$ROOT/$a" ] || { echo "ERROR: missing $ROOT/$a  (see README: you must supply it)"; exit 1; }
done

echo "== ssh key =="
[ -f "$KEY" ] || ssh-keygen -t ed25519 -N "" -f "$KEY" -C genera-vm

echo "== cloud-init seed =="
sed "s|__PUBKEY__|$(cat "$KEY.pub")|" "$HERE/seed/user-data.template" > "$HERE/seed/user-data"
xorriso -as mkisofs -output "$HERE/seed.iso" -volid cidata -joliet -rock \
  "$HERE/seed/user-data" "$HERE/seed/meta-data" >/dev/null 2>&1

echo "== disk image =="
[ -f "$HERE/debian.qcow2" ] || wget -q --show-progress -O "$HERE/debian.qcow2" "$IMG_URL"
if [ ! -f "$HERE/debian.vdi" ]; then
  qemu-img convert -f qcow2 -O vdi "$HERE/debian.qcow2" "$HERE/debian.vdi"
  VBoxManage modifymedium disk "$HERE/debian.vdi" --resize 12288
fi

echo "== create VM =="
if ! VBoxManage list vms | grep -q "\"$VM\""; then
  VBoxManage createvm --name "$VM" --ostype Debian_64 --register
  # 64-bit guests need ioapic+pae or systemd panics ("Attempted to kill init").
  VBoxManage modifyvm "$VM" --memory 3072 --cpus 2 --ioapic on --pae on \
    --graphicscontroller vmsvga --vram 16
  VBoxManage modifyvm "$VM" --nic1 nat --nictype1 virtio \
    --natpf1 "ssh,tcp,127.0.0.1,2222,,22"
  VBoxManage storagectl "$VM" --name virtio --add virtio-scsi --bootable on
  VBoxManage storageattach "$VM" --storagectl virtio --port 0 --device 0 \
    --type hdd --medium "$HERE/debian.vdi"
  VBoxManage storagectl "$VM" --name ide --add ide
  VBoxManage storageattach "$VM" --storagectl ide --port 0 --device 0 \
    --type dvddrive --medium "$HERE/seed.iso"
fi
VBoxManage list runningvms | grep -q "\"$VM\"" || VBoxManage startvm "$VM" --type headless

echo -n "== waiting for VM ssh (cloud-init installs packages, be patient) "
for _ in $(seq 1 120); do "$HERE/vmssh" true >/dev/null 2>&1 && break; echo -n .; sleep 4; done; echo
"$HERE/vmssh" true >/dev/null 2>&1 || { echo "ERROR: VM never came up on ssh"; exit 1; }
"$HERE/vmssh" 'sudo cloud-init status --wait' || true

echo "== deploy guest scripts + assets =="
"$HERE/vmssh" 'mkdir -p /home/genera/genera'
"$HERE/vmscp" "$HERE/guest/"*.sh "$HERE/guest/genera-displayfix.c" genera@127.0.0.1:/home/genera/genera/
"$HERE/vmscp" "${ASSETS[@]/#/$ROOT/}" genera@127.0.0.1:/home/genera/genera/

echo "== provision inside VM =="
"$HERE/vmssh" 'bash /home/genera/genera/provision.sh'

echo
echo "VM '$VM' is ready. Launch Genera with VNC:"
echo "    $ROOT/run-genera-vm-vnc.sh"
