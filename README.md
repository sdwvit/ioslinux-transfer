# ioslinux-transfer

Reliable tools for transferring photos and videos from an iPhone to Linux, verifying transfer integrity, and keeping a secondary backup drive synchronized.

The workflow is designed to make it safe to remove media from the iPhone after confirming that:

- all expected files were copied successfully;
- transferred files match the originals by size;
- edited versions are preserved where applicable;
- a secondary backup is synchronized with the primary archive.

The scripts in this repository are based on a transfer workflow tested against common iPhone/Linux USB and AFC failure modes.

## Quick start

```bash
sudo apt install libimobiledevice-utils ifuse usbmuxd rsync sqlite3   # Debian/Ubuntu

./check-device.sh
./copy-iphone.sh DCIM                /media/master/photos/iphone/DCIM
./copy-iphone.sh PhotoData/Mutations /media/master/photos/iphone/Mutations

ifuse -o ro /tmp/iphone
./verify.sh /tmp/iphone/DCIM /media/master/photos/iphone/DCIM

./sync-replica.sh /media/master/photos /media/backup/photos
./sync-replica.sh /media/master/photos /media/backup/photos --apply
```

## Scripts

| Script | Description |
|---|---|
| `copy-iphone.sh <phone-subdir> <dest>` | Mounts the iPhone read-only over AFC using `ifuse` and copies files with `rsync`. If the connection is interrupted, the script waits for the device, re-establishes pairing and the mount, and resumes the transfer. If the destination drive becomes unavailable, the transfer pauses until it returns. The script does not modify files on the iPhone. |
| `check-device.sh [--watch]` | Reports USB configuration, `usbmuxd` visibility, pairing status, and processes currently accessing the device. `--watch` refreshes the status once per second. |
| `inspect-library.sh <mount>` | Inspects a copy of the Photos database and reports photo/video counts, edited assets, Shared Album content, and iCloud Photos status. Useful for determining which data should be copied in addition to `DCIM`. |
| `verify.sh <phone-subdir> <dest>` | Verifies that every source file has a corresponding destination file with the same size. An `OK` result indicates that the checked files were transferred successfully. |
| `sync-replica.sh <master> <follower> [--apply]` | Performs one-way synchronization from a primary archive to a backup drive. By default, it previews changes and reports conflicts. With `--apply`, replaced or removed files from the backup are preserved under `_sync_conflicts/<timestamp>/`. |

## iPhone photo storage layout

- **`DCIM/1xxAPPLE/`** contains camera-roll originals such as `.HEIC`, `.JPG`, `.MOV`, and `.PNG` files. Live Photos typically include a `.MOV` file alongside the corresponding image. `.AAE` files contain edit metadata.

- **`PhotoData/Mutations/`** contains rendered versions of media edited in the Photos app, typically as `FullSizeRender.jpg` or `.mov`. Copy this directory if preserving edited versions is important.

- **Shared Albums** are stored through iCloud separately from the local camera roll. Removing items from the camera roll does not necessarily affect Shared Album copies.

- The storage usage reported by the Photos app is usually larger than the size of `DCIM` because it also includes rendered edits, thumbnails, databases, and caches.

- If **iCloud Photos is disabled**, the iPhone may contain the only copy of the original media.

- If **iCloud Photos is enabled with Optimize iPhone Storage**, some full-resolution originals may exist only in iCloud. In that case, use a tool such as [icloudpd](https://github.com/icloud-photos-downloader/icloud_photos_downloader) to download the cloud originals separately. Note that deleting an item from an iPhone using iCloud Photos also deletes it from iCloud.

## Transfer recommendations

1. **Prefer AFC through `ifuse`.**  
   AFC is the file-transfer protocol used by Apple device-management software and is generally more reliable for long-running transfers than the PTP-based paths exposed through `gphoto2`, KDE `camera:/`, or GNOME GVFS.

2. **Unlock the iPhone and confirm Trust before starting.**  
   PTP-based applications may cache the device state when a session begins. Connecting before the device is fully available can result in an empty or incomplete photo listing for that session.

3. **Close file-manager windows accessing the iPhone.**  
   Processes such as KDE's `kio_kamera` or `gvfs-gphoto2` may retain access to the USB device and prevent other tools from communicating with it. A `dolphin camera:/` process can also remain active after the corresponding window has been closed. Use `check-device.sh` to identify competing processes.

4. **Physically disconnect the cable when resetting the connection.**  
   On some Plasma configurations, using the eject/remove action can leave the iPhone with no active USB configuration (`cfg=[]` in `check-device.sh`). Disconnecting and reconnecting the cable reliably reinitializes the device.

5. **Ensure failed connection attempts release their resources.**  
   Retry loops are most reliable when every failed attempt closes file descriptors and releases USB handles before reconnecting.

6. **Avoid concurrent access to the `ifuse` mount during transfers.**  
   Allow the copy operation exclusive access to the mount. Running operations such as `find` or `du` concurrently may stall AFC. If the mount becomes unresponsive:

   ```bash
   fusermount -uz /tmp/iphone
   ```

   Then remount the device.

7. **Use a reliable USB port and cable.**  
   If `lsusb` detects the iPhone but `idevice_id -l` does not, try a different USB controller or motherboard port, followed by a different cable. Restarting `usbmuxd` may also help:

   ```bash
   sudo systemctl restart usbmuxd
   ```

8. **Keep the iPhone awake during long transfers.**  
   Temporarily set:

   `Settings → Display & Brightness → Auto-Lock → Never`

9. **Keep the destination drive connected.**  
   `copy-iphone.sh` pauses if the destination disappears. If an exFAT drive is disconnected during a write operation, a read-only filesystem check can be useful:

   ```bash
   fsck.exfat -n /dev/<device>
   ```

10. **Account for coarse FAT/exFAT timestamps.**  
    When comparing files by modification time, use:

    ```bash
    --modify-window=2
    ```

11. **Terminate processes by PID where possible.**  
    `pkill -f <pattern>` can also match the shell process invoking it when the search pattern is present in the command line.

## Freeing space on the iPhone

Before deleting media from the iPhone, confirm that:

1. `verify.sh` reports `OK` for `DCIM`;
2. `PhotoData/Mutations` has been copied if edited versions need to be retained;
3. the primary archive has been synchronized to the backup drive.

Media can then be removed using the Photos app and permanently deleted from **Recently Deleted**.

These scripts intentionally do not perform any deletion on the iPhone.

## Performance

Typical transfer throughput is approximately **15–25 MB/s**, depending on the device, media mix, USB connection, and filesystem.

For example, transferring 70 GB will typically take roughly one hour at the upper end of that range.

Several factors affect performance:

- **Lightning iPhones use USB 2.0.**  
  Lightning-based iPhones communicate over USB 2.0 High Speed at 480 Mbit/s. `check-device.sh` typically reports this as `speed=480M`. After protocol overhead, practical USB throughput is substantially lower than the theoretical maximum.

- **AFC is latency-sensitive.**  
  Reads pass through `usbmuxd`, AFC, and the `ifuse` FUSE filesystem. File-transfer performance is therefore affected by per-request latency as well as raw USB bandwidth.

- **Photo libraries contain many relatively small files.**  
  Typical HEIC and JPEG images are only a few megabytes each, so file open/close and metadata operations represent a meaningful portion of the total transfer time. Large video files generally achieve higher sustained throughput.

### USB-C iPhones

USB-C iPhone Pro models beginning with the iPhone 15 Pro support USB 3 transfer rates of up to 10 Gbit/s when used with a compatible USB 3 cable.

Other USB-C iPhone models may still operate at USB 2.0 data rates.

Regardless of the device, a single sequential copy process is generally the most reliable approach when transferring through AFC.

## License

MIT
