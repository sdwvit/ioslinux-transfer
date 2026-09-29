#!/usr/bin/env bash
# Diagnose why an iPhone isn't reachable on Linux. Read-only; changes nothing.
#
# Usage: ./check-device.sh            one-shot report
#        ./check-device.sh --watch    print state changes every 1s (Ctrl-C to stop)
set -u
APPLE_VID=05ac

state() {
  local usb="none" d
  for d in /sys/bus/usb/devices/*; do
    [ "$(cat "$d/idVendor" 2>/dev/null)" = "$APPLE_VID" ] || continue
    usb="bus=$(cat "$d/busnum") dev=$(cat "$d/devnum") cfg=[$(cat "$d/bConfigurationValue")] speed=$(cat "$d/speed")M"
  done
  local mux; mux=$(timeout 3 idevice_id -l 2>/dev/null | tr '\n' ' ')
  echo "usb: $usb | usbmuxd: ${mux:-none}"
}

if [ "${1:-}" = "--watch" ]; then
  prev=""
  while true; do cur=$(state); [ "$cur" != "$prev" ] && echo "$(date +%T) $cur"; prev=$cur; sleep 1; done
fi

echo "== State";            state
echo "== Pairing";          timeout 5 idevicepair validate 2>&1
echo "== usbmuxd";          systemctl show usbmuxd -p ActiveState,ExecMainStartTimestamp 2>/dev/null
echo "== Processes that commonly grab the phone"
ps -eo pid,etime,cmd | grep -E '[k]io_kamera|[g]vfsd?-gphoto|[g]vfsd?-afc|[d]olphin camera:|[g]photo2' || echo "(none)"
echo "== Holders of Apple USB device nodes"
for d in /sys/bus/usb/devices/*; do
  [ "$(cat "$d/idVendor" 2>/dev/null)" = "$APPLE_VID" ] || continue
  node=$(printf '/dev/bus/usb/%03d/%03d' "$(cat "$d/busnum")" "$(cat "$d/devnum")")
  echo "$node"; fuser -v "$node" 2>&1 | grep -v '^$' || true
done
cat <<'EOF'

Hints:
  cfg=[]           -> device unconfigured (e.g. after Plasma "Remove"/eject). Replug.
                      If it persists, restart the phone.
  usb ok, usbmuxd none -> sudo systemctl restart usbmuxd; try another port/cable.
  kio_kamera/gvfs-gphoto holding it -> close file-manager windows on the phone.
EOF
