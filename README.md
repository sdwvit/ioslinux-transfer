# ioslinux-transfer

Move every photo and video from your iPhone to Linux, double-check that each file arrived
safely, and keep a backup drive in sync. Then you can free up space on your phone with
confidence. 📸➡️🐧

These scripts came out of a long afternoon of trial and error. What's here is the approach
that turned out to work smoothly, so you can skip straight to it.

## Quick start

```bash
sudo apt install libimobiledevice-utils ifuse usbmuxd rsync sqlite3   # Debian/Ubuntu

./check-device.sh                    # is the phone visible and paired?
./copy-iphone.sh DCIM                /media/master/photos/iphone/DCIM
./copy-iphone.sh PhotoData/Mutations /media/master/photos/iphone/Mutations   # your edited versions
ifuse -o ro /tmp/iphone && ./verify.sh /tmp/iphone/DCIM /media/master/photos/iphone/DCIM
./sync-replica.sh /media/master/photos /media/backup/photos            # preview + conflict report
./sync-replica.sh /media/master/photos /media/backup/photos --apply    # sync for real
```

## The scripts

| Script | What it does for you |
|---|---|
| `copy-iphone.sh <phone-subdir> <dest>` | Mounts the phone read-only over AFC (`ifuse`) and copies with rsync. If the connection drops, it waits for the phone, re-pairs, remounts and picks up right where it left off. If the destination drive goes away, it pauses patiently until it's back. Your phone stays exactly as it was. |
| `check-device.sh [--watch]` | A friendly health check: USB configuration, usbmuxd visibility, pairing status, and which programs are talking to the phone. `--watch` shows live changes every second. |
| `inspect-library.sh <mount>` | Peeks into a copy of the Photos database and tells you how many photos and videos you have, how many you've edited, what lives in Shared Albums, and whether iCloud Photos is on. Great for knowing what to copy beyond `DCIM`. |
| `verify.sh <phone-subdir> <dest>` | Confirms every file on the phone has a matching copy with the same size. A green "OK" means you're good to go. |
| `sync-replica.sh <master> <follower> [--apply]` | Keeps a backup drive in step with your main drive, one way. First it shows a preview with any conflicts (files that differ, files only on the backup). With `--apply`, anything it replaces or removes on the backup is tucked safely into `_sync_conflicts/<timestamp>/`. |

## What lives where on your iPhone

- **`DCIM/1xxAPPLE/`** holds your camera roll originals (`.HEIC`, `.JPG`, `.MOV`, `.PNG`), the
  video half of Live Photos (a `.MOV` beside its `.HEIC`), and small `.AAE` edit sidecars.
- **`PhotoData/Mutations/`** holds the finished versions of photos you edited on the phone
  (`FullSizeRender.jpg` / `.mov`). Copy this folder too if you'd like to keep your edits.
- **Shared Albums** live in iCloud, separate from your camera roll, so they stay put when you
  tidy up the camera roll.
- The Photos app's storage number is a bit bigger than `DCIM` because it also counts edits,
  thumbnails and caches.
- **iCloud Photos off?** Your phone holds the only copy, so these scripts are your backup.
  **iCloud Photos on with "Optimize iPhone Storage"?** Some originals live only in iCloud; grab
  those with [icloudpd](https://github.com/icloud-photos-downloader/icloud_photos_downloader).
  Keep in mind that deleting on the phone also deletes from iCloud in this mode.

## Tips for a smooth transfer

1. **Go with AFC (`ifuse`).** It's the same channel iTunes uses and it's very dependable. The
   camera/PTP route (gphoto2, KDE `camera:/`, GNOME gphoto) tends to get stuck after the first
   session.
2. **Tap *Trust* and unlock before connecting.** PTP tools read the photo list once at the
   start of a session, so an early connection can show an empty phone for the whole session.
3. **Close file-manager windows showing the phone.** Dolphin's `kio_kamera` worker and
   `gvfs-gphoto2` like to hold on to the device, which leaves other tools waiting. A
   `dolphin camera:/` process can keep running after its window closes, so check with
   `check-device.sh`.
4. **Unplug the cable to disconnect.** Plasma's "Remove"/eject action leaves the iPhone
   unconfigured (`cfg=[]` in `check-device.sh`), and a quick replug brings it back.
5. **Let each connection attempt clean up after itself.** Retry loops work best when every
   failed attempt releases the USB handle before the next one.
6. **Give the `ifuse` mount one job at a time.** Let rsync have the mount to itself while it
   copies; browsing with `find` or `du` at the same moment can freeze AFC. If that happens,
   `fusermount -uz` and remount.
7. **Pick a solid USB port and cable.** If `lsusb` sees the phone but `idevice_id -l` comes up
   empty, try a rear motherboard port or a different USB controller, then a different cable,
   then `sudo systemctl restart usbmuxd`. Switching controllers made all the difference for us.
8. **Keep the phone awake.** Settings → Display & Brightness → Auto-Lock → Never, just for the
   transfer.
9. **Keep the destination drive plugged in.** `copy-iphone.sh` pauses if the drive goes away.
   If it was unplugged mid-copy, a quick `fsck.exfat -n` gives you peace of mind.
10. **exFAT and FAT store timestamps coarsely.** Use `--modify-window=2` when comparing by
    size and time.
11. **Stop processes by PID.** `pkill -f <pattern>` also matches the shell running it when the
    pattern appears in its command line.

## Freeing space on your phone

Once `verify.sh` reports OK for `DCIM`, you've copied `PhotoData/Mutations` (if you edit on
your phone), and your backup is synced, you're all set. Delete from the Photos app and empty
*Recently Deleted*. The scripts leave deleting entirely up to you.

## How long it takes

Plan on roughly **15–25 MB/s**, about an hour for every 70 GB. A good time for a coffee ☕

Here's where that number comes from:

- **Lightning is USB 2.0.** Every Lightning iPhone connects at USB 2.0 High Speed (480 Mbit/s),
  whatever cable or port you use. You can see it in `check-device.sh` as `speed=480M`. After
  USB protocol overhead that leaves about 35–40 MB/s in practice.
- **AFC runs one request at a time.** Each read travels through usbmuxd and `ifuse` (a
  single-threaded FUSE filesystem) and waits for its reply before the next begins, which
  brings typical throughput to 15–25 MB/s.
- **Photos are small files.** A typical HEIC or JPG is 2–5 MB, so opening and closing each
  file takes a noticeable share of the time. Big videos stream at the top of the range, while
  batches of photos sit toward the bottom.

**Want it faster?** USB-C iPhone Pro models (iPhone 15 Pro and later) support USB 3 at up to
10 Gbit/s when paired with a USB 3 cable, which is dramatically quicker. Other USB-C iPhones
run at USB 2.0 speeds, just like Lightning. On any model, a single steady copy job is the
sweet spot: it keeps AFC happy and finishes reliably.

## License

MIT
