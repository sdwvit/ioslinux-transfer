#!/usr/bin/env bash
# Resilient iPhone -> local disk copy over AFC (libimobiledevice + ifuse).
#
# - Mounts the phone READ-ONLY; never modifies or deletes anything on the phone.
# - Retries forever-ish: if usbmuxd loses the phone or the mount hangs, it waits
#   for the device, remounts and resumes rsync (already-copied files are skipped).
# - Pauses if the destination drive disappears instead of writing elsewhere.
#
# Usage:
#   ./copy-iphone.sh <subdir-on-phone> <destination-dir> [mountpoint]
# Examples:
#   ./copy-iphone.sh DCIM               /media/master/photos/iphone/DCIM
#   ./copy-iphone.sh PhotoData/Mutations /media/master/photos/iphone/Mutations
#
# Env:
#   DEST_MOUNT   mountpoint that must be mounted for the copy to proceed
#                (default: auto-detected from destination-dir via findmnt)
#   LOG          log file (default: ./copy-iphone.log)
#   MAX_ATTEMPTS rsync attempts before giving up (default: 500)
set -u

SRC_SUB="${1:?usage: $0 <subdir-on-phone> <destination-dir> [mountpoint]}"
DST="${2:?usage: $0 <subdir-on-phone> <destination-dir> [mountpoint]}"
M="${3:-${XDG_RUNTIME_DIR:-/tmp}/iphone-afc}"
LOG="${LOG:-./copy-iphone.log}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-500}"

log() { echo "$(date +%T) $*" | tee -a "$LOG"; }

for bin in idevice_id idevicepair ifuse rsync fusermount findmnt; do
  command -v "$bin" >/dev/null || { echo "missing: $bin (see README)"; exit 1; }
done

mkdir -p "$M"

if [ -z "${DEST_MOUNT:-}" ]; then
  probe="$DST"; while [ ! -e "$probe" ]; do probe=$(dirname "$probe"); done
  DEST_MOUNT=$(findmnt -no TARGET -T "$probe")
fi
log "destination $DST (must stay mounted: $DEST_MOUNT)"

device_visible() { [ -n "$(timeout 3 idevice_id -l 2>/dev/null)" ]; }

wait_device() {
  local said=0
  until device_visible; do
    [ $said -eq 0 ] && log "waiting for iPhone on usbmuxd (unlock it / replug / restart usbmuxd)"
    said=1; sleep 1
  done
  until timeout 5 idevicepair validate >/dev/null 2>&1; do
    log "not paired - requesting pairing, tap 'Trust' on the phone"
    timeout 10 idevicepair pair >/dev/null 2>&1; sleep 1
  done
}

mount_phone() {
  fusermount -uz "$M" 2>/dev/null
  wait_device
  until timeout 15 ifuse -o ro "$M" 2>/dev/null && timeout 10 ls "$M/$SRC_SUB" >/dev/null 2>&1; do
    fusermount -uz "$M" 2>/dev/null; sleep 1; wait_device
  done
  log "mounted phone at $M (read-only)"
}

cleanup() { fusermount -uz "$M" 2>/dev/null; }
trap cleanup EXIT

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  until mountpoint -q "$DEST_MOUNT"; do log "destination $DEST_MOUNT NOT MOUNTED - paused"; sleep 5; done
  timeout 10 ls "$M/$SRC_SUB" >/dev/null 2>&1 || mount_phone
  mkdir -p "$DST"
  log "rsync attempt $attempt: $SRC_SUB -> $DST"
  # -r recursive, -t keep mtimes; no -p/-o/-g (phone perms are meaningless, exFAT has none).
  # --modify-window=2 tolerates FAT/exFAT timestamp granularity.
  # --timeout makes a hung AFC connection fail fast instead of stalling forever.
  rsync -rt --modify-window=2 --partial-dir=.rsync-partial --timeout=30 \
        --info=stats1 "$M/$SRC_SUB/" "$DST/" >>"$LOG" 2>&1
  rc=$?
  log "rsync exit=$rc"
  if [ $rc -eq 0 ]; then log "DONE $SRC_SUB"; exit 0; fi
  sleep 1
done
log "GAVE UP after $MAX_ATTEMPTS attempts"; exit 1
