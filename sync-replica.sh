#!/usr/bin/env bash
# One-way master -> follower sync with a conflict report first.
#
# Compares by size + mtime (fast). Never writes to the master.
# Conflicts reported:
#   - files that exist on both but differ (would be overwritten on follower)
#   - files that exist only on the follower (would be deleted)
# Anything replaced/deleted on the follower is moved to
# <follower>/../_sync_conflicts/<timestamp>/ instead of being destroyed.
#
# Usage:
#   ./sync-replica.sh <master-dir> <follower-dir>          dry run + report only
#   ./sync-replica.sh <master-dir> <follower-dir> --apply  actually sync
set -u
MASTER="${1:?usage: $0 <master-dir> <follower-dir> [--apply]}"
FOLLOWER="${2:?usage: $0 <master-dir> <follower-dir> [--apply]}"
APPLY="${3:-}"
MASTER="${MASTER%/}"; FOLLOWER="${FOLLOWER%/}"
REPORT="$(mktemp)"

OPTS=(-rt --modify-window=2 --delete)

rsync -n "${OPTS[@]}" --itemize-changes --out-format='%i %l %n' "$MASTER/" "$FOLLOWER/" > "$REPORT"

new=$(grep -c '^>f+++++++' "$REPORT")
changed=$(grep '^>f' "$REPORT" | grep -vc '^>f+++++++')
extra=$(grep -c '^\*deleting' "$REPORT")
timeonly=$(grep -c '^\.f' "$REPORT")

echo "== Dry run: $MASTER  ->  $FOLLOWER"
echo "new on master (will copy):          $new"
echo "CONFLICT differ (size/mtime):       $changed"
echo "CONFLICT only on follower:          $extra"
echo "timestamp-only differences:         $timeonly"
[ "$changed" -gt 0 ] && { echo; echo "-- differ:"; grep '^>f' "$REPORT" | grep -v '^>f+++++++'; }
[ "$extra" -gt 0 ]   && { echo; echo "-- only on follower:"; grep '^\*deleting' "$REPORT"; }
echo "(full itemized report: $REPORT)"

if [ "$APPLY" != "--apply" ]; then
  echo; echo "Dry run only. Re-run with --apply to sync."
  exit 0
fi

BACKUP="$(dirname "$FOLLOWER")/_sync_conflicts/$(date +%Y%m%d-%H%M%S)"
echo; echo "== Applying. Replaced/deleted follower files go to: $BACKUP"
rsync "${OPTS[@]}" --backup --backup-dir="$BACKUP" --info=progress2 "$MASTER/" "$FOLLOWER/"
rc=$?
echo "rsync exit=$rc"
exit $rc
