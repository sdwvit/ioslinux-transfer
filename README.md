# ioslinux-transfer

Get all photos and videos off an iPhone on Linux **reliably**, verify them, and keep a
backup replica in sync, so you can free space on the phone without losing anything.

Written after a long fight with KDE/gphoto2/PTP. This is the approach that actually works.

## TL;DR

```bash
sudo apt install libimobiledevice-utils ifuse usbmuxd rsync sqlite3   # Debian/Ubuntu

./check-device.sh                    # is the phone visible & paired?
./copy-iphone.sh DCIM                /media/master/photos/iphone/DCIM
./copy-iphone.sh PhotoData/Mutations /media/master/photos/iphone/Mutations   # edited versions
ifuse -o ro /tmp/iphone && ./verify.sh /tmp/iphone/DCIM /media/master/photos/iphone/DCIM
./sync-replica.sh /media/master/photos /media/backup/photos            # dry run + conflict report
./sync-replica.sh /media/master/photos /media/backup/photos --apply
```

## Scripts

| Script | What it does |
|---|---|
| `copy-iphone.sh <phone-subdir> <dest>` | Mounts the phone **read-only** via AFC (`ifuse`) and rsyncs. Survives disconnects: waits for the device, re-pairs if needed, remounts, resumes. Pauses if the destination drive disappears. Never deletes anything. |
| `check-device.sh [--watch]` | Read-only diagnostics: USB configuration, usbmuxd visibility, pairing, and which processes hold the device. `--watch` prints state changes every second. |
| `inspect-library.sh <mount>` | Reads a copy of `Photos.sqlite`: asset counts, how many are edited, shared-album items, iCloud state. Tells you what `DCIM` alone would miss. |
| `verify.sh <phone-subdir> <dest>` | Checks that every phone file exists in the copy with identical size. Exit 0 = safe. |
| `sync-replica.sh <master> <follower> [--apply]` | One-way master→follower sync. Dry run first with a **conflict report** (files that differ, files only on follower). With `--apply`, anything replaced/removed on the follower is moved to `_sync_conflicts/<timestamp>/`, not destroyed. |

## What is on the phone (and what DCIM misses)

- `DCIM/1xxAPPLE/`: camera-roll originals (`.HEIC`, `.JPG`, `.MOV`, `.PNG`), Live Photo
  video halves (`.MOV` next to the `.HEIC`), and `.AAE` edit sidecars.
- `PhotoData/Mutations/`: **rendered edited versions** (`FullSizeRender.jpg/.mov`). If you
  edited photos on the phone and only copy `DCIM`, you keep the unedited originals only.
- Shared Albums live in iCloud, not in the camera roll; deleting the camera roll doesn't touch them.
- The Photos app's "storage used" number is larger than `DCIM` because it includes edits,
  thumbnails and caches.
- If **iCloud Photos is off**, the phone is the only copy. If it's **on** with "Optimize
  iPhone Storage", some originals are not on the phone at all (use
  [icloudpd](https://github.com/icloud-photos-downloader/icloud_photos_downloader) for those), and
  deleting on the phone deletes from iCloud too.

## Pitfalls we hit (so you don't)

1. **Use AFC (`ifuse`), not PTP (gphoto2 / KDE `camera:/` / GNOME gphoto).** PTP on iPhones is
   fragile: after one session closes, new sessions often time out until you replug.
2. **gphoto2 caches empty listings.** If a PTP session opens before you tap *Trust* or unlock,
   it reports an empty store and keeps it that way for the whole session.
3. **File managers grab the device.** Dolphin's `kio_kamera` worker, or `gvfs-gphoto2`, claims
   the USB interface; everything else then gets "Could not claim the USB device". Close any
   file-manager window showing the phone. Note that a `dolphin camera:/` process can outlive its window.
4. **Plasma's "Remove"/eject leaves the iPhone unconfigured** (`bConfigurationValue` empty).
   Nothing can talk to it until you physically replug. `check-device.sh` shows `cfg=[]`.
5. **Don't hammer the device with retry loops that don't release it.** A failed init that keeps
   the USB handle open blocks every later attempt, including usbmuxd.
6. **One reader at a time on an `ifuse` mount.** Running `find`/`du` on the mount while rsync
   copies can hang AFC; then even `ls` blocks. Unmount (`fusermount -uz`) and remount.
7. **usbmuxd can silently lose the phone** under sustained load while USB stays connected
   (`lsusb` shows it, `idevice_id -l` doesn't). Fixes, in order: a different **USB port or
   controller** (rear motherboard ports), a different **cable**, `sudo systemctl restart usbmuxd`.
   Moving the phone to another USB controller fixed it for us.
8. **Keep the phone unlocked** (Settings → Display → Auto-Lock → Never, during transfer).
9. **Don't unplug the destination drive mid-copy.** `copy-iphone.sh` pauses if it disappears;
   run a filesystem check (`fsck.exfat -n`) before trusting it again.
10. **exFAT/FAT timestamps**: use `--modify-window=2` for size+mtime comparisons.
11. **`pkill -f <pattern>`** also matches the shell that runs it if the pattern appears in the
    command line. Kill by PID.

## Freeing space on the phone

Only after `verify.sh` passes for `DCIM` **and** you've copied `PhotoData/Mutations` (if you
edit on the phone) **and** the replica sync is done. Then delete in the Photos app and empty
*Recently Deleted*. These scripts never delete anything on the phone.

## Speed

Expect ~15–25 MB/s over USB 2 AFC (≈ 1 hour per 70 GB).

## License

MIT
