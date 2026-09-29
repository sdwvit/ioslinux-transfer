#!/usr/bin/env bash
# Verify a copy against the phone: every file present with identical size.
# Read-only on both sides. Prints any missing/mismatched files.
#
# Usage: ./verify.sh <phone-mountpoint>/<subdir> <destination-dir>
# Exit 0 only if every file on the phone exists in the destination with the same size.
set -u
SRC="${1:?usage: $0 <phone-subdir> <destination-dir>}"
DST="${2:?usage: $0 <phone-subdir> <destination-dir>}"

# rsync dry run with size-only comparison lists anything missing or different.
out=$(rsync -rn --size-only --out-format='%n' --exclude='.rsync-partial/' "$SRC/" "$DST/" 2>&1 | grep -v '/$')
src_n=$(find "$SRC" -type f | wc -l)
dst_n=$(find "$DST" -type f -not -path '*/.rsync-partial/*' | wc -l)
src_b=$(find "$SRC" -type f -printf '%s\n' | awk '{s+=$1} END{print s+0}')
dst_b=$(find "$DST" -type f -not -path '*/.rsync-partial/*' -printf '%s\n' | awk '{s+=$1} END{print s+0}')

echo "phone: $src_n files, $src_b bytes"
echo "copy : $dst_n files, $dst_b bytes"
if [ -z "$out" ]; then
  echo "OK: every phone file is present in the copy with matching size."
  exit 0
fi
echo "MISSING or DIFFERENT ($(echo "$out" | wc -l)):"
echo "$out"
exit 1
