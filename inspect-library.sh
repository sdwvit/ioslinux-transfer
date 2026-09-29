#!/usr/bin/env bash
# Inspect the iPhone Photos library database to learn what DCIM alone would miss.
# Reads a COPY of Photos.sqlite; never touches the phone's database in place.
#
# Usage: ./inspect-library.sh <phone-mountpoint> [workdir]
# (mount first: ifuse -o ro <mountpoint>)
set -eu
M="${1:?usage: $0 <phone-mountpoint> [workdir]}"
W="${2:-$(mktemp -d)}"
command -v sqlite3 >/dev/null || { echo "missing: sqlite3"; exit 1; }

cp "$M"/PhotoData/Photos.sqlite* "$W"/
DB="$W/Photos.sqlite"
q() { sqlite3 -readonly "$DB" "$1"; }

echo "== Assets (excluding Recently Deleted)"
q "select 'total', count(*) from ZASSET where ZTRASHEDSTATE=0;"
q "select case ZKIND when 0 then 'photos' when 1 then 'videos' else 'kind '||ZKIND end, count(*) from ZASSET where ZTRASHEDSTATE=0 group by ZKIND;"
q "select 'in Recently Deleted', count(*) from ZASSET where ZTRASHEDSTATE=1;"

echo "== Where originals live"
q "select case when ZDIRECTORY like 'DCIM/%' then 'DCIM (camera roll)'
               when ZDIRECTORY like 'PhotoData/PhotoCloudSharingData%' then 'Shared Albums (iCloud)'
               else 'other' end, count(*)
   from ZASSET where ZTRASHEDSTATE=0 group by 1;"

echo "== Edited photos (edited renders are in PhotoData/Mutations, NOT in DCIM)"
q "select 'edited assets', count(*) from ZASSET where ZTRASHEDSTATE=0 and ZADJUSTMENTSSTATE>0;"
du -sh "$M/PhotoData/Mutations" 2>/dev/null || true

echo "== iCloud Photos state (ZCLOUDLOCALSTATE)"
q "select ZCLOUDLOCALSTATE, count(*) from ZASSET where ZTRASHEDSTATE=0 group by 1;"
echo "   0 for everything usually means iCloud Photos is off: the phone holds the ONLY copy."

echo "== Total original size per DB"
q "select round(sum(b.ZORIGINALFILESIZE)/1e9,2)||' GB' from ZASSET a join ZADDITIONALASSETATTRIBUTES b on b.ZASSET=a.Z_PK where a.ZTRASHEDSTATE=0;"
echo "(DB copy kept in $W)"
